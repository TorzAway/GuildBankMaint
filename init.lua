-- =============================================================================
-- gbank_helper.lua
-- Guild Bank Automation Script for MacroQuest (MQ Lua)
-- Version 4.7
-- Save as `gbank_helper.lua` in your MacroQuest `lua` folder.
-- Run in-game with: /lua run gbank_helper
-- =============================================================================
--
-- OVERVIEW
-- --------
-- Automates guild bank interactions for Anguish Mat farming and
-- Spell/Song/Skill/Tome management. Provides an ImGui UI with category and
-- mode selection, picker windows for selective withdraw/deposit, officer-only
-- tools, and a unified colored notification system.
--
-- REQUIREMENTS
-- ------------
-- - MacroQuest with Lua and ImGui support
-- - MQ Navigation plugin (for auto-pathing to Guild Treasurer)
-- - Guild membership (officer rank required for PROMOTE, PRUNE SPELLS,
--   and MERGE STACKS)
-- - GuildManagementWnd must be openable in-game
--
-- USAGE
-- -----
-- 1. Run: /lua run gbank_helper
-- 2. Open the Guild Management window before starting (for rank detection).
-- 3. Select a Category (Anguish Mats or Spells/Songs/Skills/Tomes).
-- 4. Select a Mode (GET to withdraw, GIVE to deposit).
-- 5. Click SCAN GUILD BANK (GET) or SCAN INVENTORY (GIVE).
-- 6. If the bank is not open, the script will navigate to the Guild Treasurer.
-- 7. A picker window will appear — select items and confirm.
--
-- WINDOW COMMANDS
-- ---------------
-- /gbmhide  Collapse the main UI window to its title bar.
-- /gbmshow  Restore the main UI window to full size.
-- (Clicking the ImGui chevron also toggles collapse; both methods notify chat.)
--
-- EXIT SCRIPT button closes the guild bank window, inventory window, and any
-- open bag windows before terminating the script.
--
-- ITEM LISTS
-- ----------
-- itemTargetList  : Anguish Mat items matched by exact name for GET/GIVE.
-- spellTargetList : Optional explicit spell/tome names (patterns auto-match).
--                   EQ naming conventions auto-detected:
--                     "Spell: *", "Song: *", "Tome of *", "Tome: *",
--                     "Skill: *", items containing "Rk. I/II/III"
-- anguishMatInfo  : Lookup table keyed by Anguish Mat name. Each entry holds:
--                     armor = armor archetype (Plate/Chain/Silk/Leather)
--                     slot  = inventory slot the mat crafts (Head/Arms/Chest/
--                             Wrist/Hands/Legs/Feet)
--                   Used to populate the Armor Type and Slot columns in the
--                   Anguish Mats picker window.
--
-- =============================================================================
-- FUNCTION REFERENCE
-- =============================================================================
--
-- NOTIFICATION
-- ------------
-- notify(tag, msg, kind)
--   Sends a colored /echo message. tag = label shown in brackets.
--   kind: "info"(yellow), "success"(green), "error"(red), "warn"(orange),
--         "scan"(teal), "action"(white), "officer"(magenta)
--
-- MATCH HELPERS
-- -------------
-- activeList()
--   Returns itemTargetList or spellTargetList based on selectedCategory.
--
-- isAnguishMatItem(itemName)
--   Returns true if itemName exactly matches an entry in itemTargetList.
--   Case-insensitive, strips leading/trailing whitespace.
--
-- isSpellItem(itemName)
--   Returns true if itemName matches EQ spell/song/skill/tome naming patterns
--   ("Spell: ", "Song: ", "Tome of ", "Tome: ", "Skill: ", "Rk. I/II/III"),
--   or matches an explicit entry in spellTargetList.
--
-- isTargetItem(itemName)
--   Routes to isAnguishMatItem or isSpellItem based on selectedCategory.
--
-- SHARED UTILITIES
-- ----------------
-- clearCursorFailsafe()
--   Checks if an item is stuck on the cursor and calls /autoinventory.
--   Aborts the active workflow if inventory is full. Returns true if safe.
--
-- handleQuantityWindow()
--   Detects the QuantityWnd popup (stacked items), sets slider to max,
--   and confirms. Waits up to 2 seconds for the item to reach the cursor.
--
-- PRUNE SPELLS ENGINE
-- -------------------
-- handlePruneSpells()
--   Called each main-loop tick while isPruning is true. Walks GBANK_ItemList,
--   identifies spell/song/skill/tome items via isSpellItem(), looks up their
--   MinCasterLevel via mq.TLO.Spell(spellName).MinCasterLevel(), and withdraws
--   any item below PRUNE_LEVEL_CUTOFF (default 65). Depending on pruneAction:
--     1 = /autoinventory (keep), 2 = /destroy (discard).
--   Yields back to the main loop after each withdrawal so slot indices
--   are re-scanned fresh on the next tick.
--
-- MERGE STACKS ENGINE
-- -------------------
-- handleMergeStacks()
--   Called from the main loop while isMerging is true. Walks every row in
--   GBANK_ItemList, selects it, and clicks GBANK_MergeButton so EQ
--   consolidates split stacks of each stackable item across the whole vault.
--   Aborts cleanly if the bank window closes mid-sweep. Sets isMerging = false
--   on completion. Officer + bank open required.
--
-- BANK SCAN CORE
-- --------------
-- doScan(matchFn, windowTitle, actionLabel, mode, logTag)
--   Internal shared scan engine. Walks GBANK_ItemList, calls matchFn() on
--   each item name, groups stacks of the same item, and populates scanResults
--   and selectedForWithdrawal (all unchecked by default). Each entry stores
--   qty = total item count across all matching stacks. Sets pickerWindowTitle,
--   pickerActionLabel, and pickerMode ("withdraw"/"deposit"). For Anguish Mat
--   matches, also looks up armor archetype and slot from anguishMatInfo and
--   stores them in the entry. Opens the picker window if any matches are found.
--   Does NOT move or touch any items.
--
-- scanBankAnguish()
--   Calls doScan with isAnguishMatItem for the Anguish Mats GET picker.
--
-- scanBankSpells()
--   Calls doScan with isSpellItem for the Spells GET picker. Looks up
--   MinCasterLevel via Spell TLO for each match to display required level.
--
-- scanBankForCategory()
--   Dispatches to scanBankAnguish or scanBankSpells based on selectedCategory.
--
-- scanInventorySpells()
--   Walks bag slots 23-32 (all main packs), runs isSpellItem on each sub-slot.
--   Looks up MinCasterLevel via FindItem + Scroll.SpellID → Spell TLO chain.
--   Populates scanResults for the deposit picker (pickerMode = "deposit").
--
-- scanInventoryAnguish()
--   Walks bag slots 23-32, runs isAnguishMatItem on each sub-slot. Looks up
--   armor archetype and slot from anguishMatInfo for each match.
--   Populates scanResults for the deposit picker (pickerMode = "deposit").
--
-- scanInventoryForCategory()
--   Dispatches to scanInventoryAnguish or scanInventorySpells.
--
-- PICKED WITHDRAWAL ENGINE
-- ------------------------
-- handlePickedWithdrawal()
--   Called each main-loop tick while isWithdrawingPicked is true. Processes
--   withdrawQueue one name per tick. Re-scans bank slot indices live after each
--   withdrawal (indices shift after each removal). Calls handleQuantityWindow()
--   for stacked items and /autoinventory after each pickup. Advances the queue
--   only once the item is fully gone from the bank list.
--
-- PICKED DEPOSIT ENGINE
-- ---------------------
-- handlePickedDeposit()
--   Called each main-loop tick while isDepositingPicked is true. Processes
--   depositQueue one name per tick. Uses FindItem("=name") to locate each item
--   in inventory, picks it up with /shift /itemnotify, then clicks
--   GBANK_DepositButton. On queue exhaustion, calls processOfficerPublicVaultRoutines
--   if cachedIsOfficer, then cleans up state.
--
-- STANDARD GET (non-picker fallback)
-- -----------------------------------
-- handleGetMode()
--   Full-sweep bank withdrawal used for non-picker flows. Walks GBANK_ItemList,
--   calls isTargetItem on each row, and withdraws the first match found per tick.
--   Sets isRunningWorkflow = false when no more matches remain.
--
-- OFFICER PUBLIC VAULT ROUTINES
-- ------------------------------
-- processOfficerPublicVaultRoutines()
--   Officer-only. Runs three sequential steps after a deposit operation:
--   Step 1 — PROMOTE: promotes all items in the GBANK_DepositList staging area
--     to the main vault by clicking GBANK_PromoteButton for each entry.
--   Step 2 — PUBLIC SWEEP: walks every row in GBANK_ItemList, reads the
--     permission from column 4, and changes any non-Public item to Public via
--     GBANK_PermissionCombo listselect 4.
--   Step 3 — MERGE STACKS: selects every row in GBANK_ItemList and clicks
--     GBANK_MergeButton to consolidate split stacks of each stackable item.
--   Only called when cachedIsOfficer is true.
--
-- GIVE MODE (Anguish Mats sweep fallback)
-- ----------------------------------------
-- handleGiveMode()
--   Legacy full-sweep deposit for Anguish Mats. Iterates activeList(), finds
--   each item in inventory via FindItem, picks it up, and deposits it.
--   Calls processOfficerPublicVaultRoutines on completion if officer.
--   (Retained for compatibility; normal GIVE now uses the picker path.)
--
-- NAVIGATION WORKFLOW
-- -------------------
-- processBankWorkflow()
--   Four-step sequenced automation:
--     Step 1: /target npc "guild treasurer" — locates nearest treasurer.
--     Step 2: /nav target — moves to the treasurer; waits for arrival.
--     Step 3: /click left target — interacts to open the bank window.
--     Step 4: Dispatches based on pending flags and selected mode:
--               pendingPrune   → sets isPruning   = true
--               pendingPromote → sets isPromoting  = true
--               pendingMerge   → sets isMerging    = true
--               GET mode       → scanBankForCategory()
--               GIVE mode      → scanInventoryForCategory()
--
-- PICKER WINDOW
-- -------------
-- pickerGUI()
--   Renders a second floating ImGui window (independent of the main window).
--   Displays scanResults as checkboxes, all unchecked by default.
--   Provides Select All / Deselect All shortcuts and a scrollable list.
--   Column layout varies by category:
--     Anguish Mats : Item | Armor Type | Slot | Qty  (4 columns)
--     Spells       : Item | Req. Level  | Qty  (3 columns)
--     Other        : Item | Qty                (2 columns)
--   The Qty column shows "current / total" for each item. When an item is
--   checked, [-] and [+] buttons let the user pick exactly how many to
--   transfer (clamped 1 to total available). selectedQty[name] stores the
--   chosen amount; it defaults to the full qty when an item is first checked.
--   All visible columns are sortable — clicking a column header sorts by that
--   field ascending; clicking again reverses to descending. The active sort
--   column shows a [^] (ascending) or [v] (descending) chevron in its header.
--   Sort state is maintained in pickerSortCol and pickerSortAsc. A stable
--   secondary sort by item name is applied when primary values are equal.
--   Confirm button (label from pickerActionLabel) builds withdrawQueue or
--   depositQueue from checked entries as {name, qty} tables, sets the
--   appropriate engine flag, and closes the window immediately.
--
-- GUILD RANK LOOKUP
-- -----------------
-- fetchGuildRank()
--   Called once at script startup from the main loop thread (delays safe).
--   Opens GuildManagementWnd via DoOpen() if not already open, waits up to
--   5 seconds for GT_MemberList to populate, scans all columns of every row
--   to find the character's own name, selects that row via listselect, waits
--   500ms for the UI to update, then reads column 4 as the rank string.
--   Caches result in cachedGuildRank and cachedIsOfficer (true for Officer/Leader).
--   Closes the window again if it was opened by this function.
--
-- MAIN GUI
-- --------
-- mainGUI()
--   ImGui render callback registered with mq.imgui.init. Renders the main
--   "Guild Bank Automator" window on every frame. Layout (top to bottom):
--     - Guild rank / officer status (color-coded green/orange)
--     - PRUNE SPELLS + PROMOTE buttons (officer only, centered on row 1)
--     - MERGE STACKS button (officer only, centered on row 2)
--     - Prune action radio: Keep (autoinv) / Destroy
--     - Separator
--     - Category radio: Anguish Mats / Spells/Songs/Skills/Tomes
--     - Separator
--     - Mode radio: GET (Withdraw) / GIVE (Deposit)
--     - Separator
--     - SCAN GUILD BANK / SCAN INVENTORY / CANCEL button (centered)
--     - Separator
--     - Status line (color-coded by current operation)
--     - Separator
--     - EXIT SCRIPT button (centered, red): stops all automation, closes
--       GuildBankWnd, InventoryWindow, and any open Pack1-Pack10, then exits.
--   Also calls pickerGUI() each frame to render the picker popup if open.
--   Collapse state is tracked each frame; clicking the ImGui chevron directly
--   also notifies chat with the appropriate /gbmshow or /gbmhide command hint.
--
-- WINDOW VISIBILITY BINDS
-- -----------------------
-- /gbmhide
--   Collapses the main window to its title bar, identical to clicking the
--   ImGui chevron. Notifies chat and echoes /gbmshow as the restore command.
--   Has no effect (warns) if the window is already collapsed.
--
-- /gbmshow
--   Restores a collapsed main window to its full size. Notifies chat and
--   echoes /gbmhide as the hide command. Has no effect (warns) if already visible.
--   Works whether the window was collapsed by /gbmhide or the chevron.
--
-- PRIMARY EXECUTION ENGINE
-- ------------------------
--   Main while loop (runs while shouldDraw is true, 50ms tick).
--   Priority order each tick:
--     1. isWithdrawingPicked → handlePickedWithdrawal()
--     2. isDepositingPicked  → handlePickedDeposit()
--     3. isPruning           → handlePruneSpells()   (officer + bank open required)
--     4. isPromoting         → processOfficerPublicVaultRoutines() (officer + bank open)
--     5. isMerging           → handleMergeStacks()   (officer + bank open required)
--     6. isRunningWorkflow   → processBankWorkflow()
--
-- =============================================================================

local mq = require('mq')
local ImGui = require('ImGui')

-- ─── Unified Notification Helper ─────────────────────────────────────────────
-- Colors: "info"=yellow, "success"=green, "error"=red, "warn"=orange,
--         "scan"=teal, "action"=white, "officer"=magenta
local COLOR = {
    info    = "\ay",  -- yellow
    success = "\ag",  -- green
    error   = "\ar",  -- red
    warn    = "\ao",  -- orange
    scan    = "\at",  -- teal
    action  = "\aw",  -- white
    officer = "\am",  -- magenta
}
local function notify(tag, msg, kind)
    local c = COLOR[kind or "info"] or COLOR.info
    mq.cmd(string.format("/echo %s[%s]\\ax \\ay%s\\ax", c, tag, msg))
end

-- Wraps a variable value in red brackets with green text for notifications.
-- Usage: notify("Tag", "Found " .. hilite(count) .. " items.", "info")
local function hilite(val)
    return "\am[\ag" .. tostring(val) .. "\am]\ay"
end


-- Global script states
local version = "4.7"
local openGUI = true
local shouldDraw = true
local windowCollapsed    = false  -- true while /gbmhide has collapsed the main window
local pendingCollapseSet = false  -- true for one frame after /gbmshow or /gbmhide to force ImGui.Always
local selectedOption = 1   -- 1 = GET, 2 = GIVE
local selectedCategory = 1 -- 1 = Anguish Mats, 2 = Spells/Songs/Skills/Tomes

-- Guild rank cache (populated once at startup from the main loop thread)
local cachedGuildRank = "Unknown"
local cachedIsOfficer = false

-- Automation Workflow States
local isRunningWorkflow = false
local workflowStep = 0
local lastActionTime = 0
local ACTION_DELAY = 800 -- Throttle actions (ms) to prevent UI spam/disconnects

-- Picker Window State (used by all scan paths)
local showPickerWindow    = false -- controls the item selection popup
local pickerWindowTitle   = ""    -- set by whichever scan opens the picker
local pickerActionLabel   = ""    -- button label: "Withdraw Selected" or "Deposit Selected"
local pickerMode          = ""    -- "withdraw" | "deposit" — drives which engine runs
local scanResults         = {}    -- { { name=string, slots={int,...}, qty=int } ... }
local selectedForWithdrawal = {}  -- keyed by name -> bool; false = unchecked (default)
local selectedQty         = {}    -- keyed by name -> int; how many the user wants to transfer
local isWithdrawingPicked = false
local withdrawQueue       = {}    -- ordered list of names to withdraw after confirmation
local isDepositingPicked  = false
local depositQueue        = {}    -- ordered list of names to deposit after confirmation
local isPruning           = false -- true while PRUNE SPELLS withdrawal is running
local pendingPrune        = false -- true when nav workflow should start prune at step 4
local pruneAction         = 1    -- 1 = autoinventory, 2 = destroy
local pickerSortCol       = "name" -- active sort column: "name" | "armor" | "slot" | "level"
local pickerSortAsc       = true   -- true = ascending, false = descending
local isPromoting         = false -- true while PROMOTE public-access sweep is running
local pendingPromote      = false -- true when nav workflow should start promote at step 4
local pendingMerge        = false -- true when nav workflow should start merge at step 4
local isMerging           = false -- true while MERGE STACKS sweep is running
local PRUNE_LEVEL_CUTOFF  = 65   -- withdraw spells below this level

-- Configuration List: Anguish Mats
local itemTargetList = {
    "Dragorn Muramite Ring", "Ikaav Head", "Kyv Scout Ring", "Kyv Short Bow",
    "Kyv Whetstone", "Shattered Ukun Hide", "Withered Discordling Tongue",
    "Bar of Nashtar Berry Soap", "Ikaav Tail", "Kuuan Whetstone",
    "Piece of Vrenlar Fruit", "Riftseeker Trinket", "Softened Feran Hide",
    "Spool of Balemoon Silk", "Bazu Nail Bracelet", "Chimera Gut String",
    "Discordling Hoof", "Fine Chimera Hide", "Muramite Noble's March Award",
    "Quality Feran Hide", "Spiked Discordling Collar", "Blackened Discordling Tail",
    "Ceremonial Dragorn Candle", "Crystal of Yearning", "Kyv Food Sack",
    "Kyv Hunter Ring", "Large Piece of Kuuan Ore", "Noc Right Hand"
}

-- Anguish Mat info table for visible armor crafting (Omens of War).
-- Each entry holds: armor archetype and inventory slot.
local anguishMatInfo = {
    --	Plate
	["Kyv Food Sack"] 				 = { armor = "Plate",   slot = "Head"  },
	["Noc Right Hand"]        		 = { armor = "Plate",   slot = "Arms" },
	["Large Piece of Kuuan Ore"]     = { armor = "Plate",   slot = "Wrist"  },
	["Crystal of Yearning"]          = { armor = "Plate",   slot = "Hands" },
	["Ceremonial Dragorn Candle"]    = { armor = "Plate",   slot = "Chest" },
	["Blackened Discordling Tail"]   = { armor = "Plate",   slot = "Legs"  },
	["Kyv Hunter Ring"]          	 = { armor = "Plate",   slot = "Feet"  },
    --  Chain
	["Kyv Scout Ring"] 				 = { armor = "Chain",   slot = "Head"  },
	["Ikaav Head"]        			 = { armor = "Chain",   slot = "Arms" },
	["Withered Discordling Tongue"]  = { armor = "Chain",   slot = "Wrist"  },
	["Kyv Whetstone"]         		 = { armor = "Chain",   slot = "Hands" },
	["Kyv Short Bow"]   			 = { armor = "Chain",   slot = "Chest" },
	["Shattered Ukun Hide"]  		 = { armor = "Chain",   slot = "Legs"  },
	["Dragorn Muramite Ring"]        = { armor = "Chain",   slot = "Feet"  },
	--  Leather
	["Muramite Noble's March Award"] = { armor = "Leather",   slot = "Head"  },
	["Spiked Discordling Collar"]    = { armor = "Leather",   slot = "Arms" },
	["Quality Feran Hide"]    		 = { armor = "Leather",   slot = "Wrist"  },
	["Fine Chimera Hide"]         	 = { armor = "Leather",   slot = "Hands" },
	["Bazu Nail Bracelet"]   		 = { armor = "Leather",   slot = "Chest" },
	["Discordling Hoof"]  			 = { armor = "Leather",   slot = "Legs"  },	
	["Chimera Gut String"]         	 = { armor = "Leather",   slot = "Feet"  },
	--  Silk
	["Bar of Nashtar Berry Soap"]	= { armor = "Silk",   slot = "Head"  },	
	["Spool of Balemoon Silk"]   	= { armor = "Silk",   slot = "Arms" },
	["Riftseeker Trinket"]    		= { armor = "Silk",   slot = "Wrist"  },
	["Kuuan Whetstone"]         	= { armor = "Silk",   slot = "Hands" },
	["Piece of Vrenlar Fruit"]   	= { armor = "Silk",   slot = "Chest" },
	["Softened Feran Hide"]  		= { armor = "Silk",   slot = "Legs"  },
	["Ikaav Tail"]          		= { armor = "Silk",   slot = "Feet"  },
}

-- Configuration List: Spells / Songs / Skills / Tomes
-- Optional explicit list — any entries here are matched in addition to the
-- EQ naming-convention patterns (Spell: / Song: / Tome of / Tome: / etc.)
local spellTargetList = {
    -- e.g. "Spell: Example Name", "Tome of Example Discipline",
}

-- Returns the active item list based on the selected category
local function activeList()
    return selectedCategory == 1 and itemTargetList or spellTargetList
end

-- ─── Match Helpers ────────────────────────────────────────────────────────────

-- Match against the Anguish Mats list
local function isAnguishMatItem(itemName)
    if not itemName or type(itemName) ~= "string" or itemName == "" then return false end
    local clean = itemName:gsub("^%s*(.-)%s*$", "%1"):lower()
    for _, name in ipairs(itemTargetList) do
        if name and name:lower() == clean then return true end
    end
    return false
end

-- Match against EQ Spell/Song/Skill/Tome naming conventions,
-- plus any entries explicitly added to spellTargetList.
local function isSpellItem(itemName)
    if not itemName or type(itemName) ~= "string" or itemName == "" then return false end
    local clean = itemName:gsub("^%s*(.-)%s*$", "%1")
    local lower = clean:lower()

    -- EQ naming-convention patterns (case-insensitive prefix check)
    if lower:find("^spell:%s") then return true end
    if lower:find("^song:%s") then return true end
    if lower:find("^tome of%s") then return true end
    if lower:find("^tome:%s") then return true end
    if lower:find("^skill:%s") then return true end
    -- Catch "Rk. II / Rk. III" variants that start with "Spell:" after a rename
    if lower:find("rk%. i") then return true end

    -- Also honour explicit spellTargetList entries if populated
    for _, name in ipairs(spellTargetList) do
        if name and name:lower() == lower then return true end
    end

    return false
end

-- Routes to the correct match function for the current category
local function isTargetItem(itemName)
    if selectedCategory == 1 then
        return isAnguishMatItem(itemName)
    else
        return isSpellItem(itemName)
    end
end

-- ─── Shared Utilities ─────────────────────────────────────────────────────────

-- Safely handles cursor blocks (full inventory / item stuck)
local function clearCursorFailsafe()
    if mq.TLO.Cursor() then
        notify("GBank", "Item stuck on cursor. Attempting to clear...", "warn")
        mq.cmd("/autoinventory")
        mq.delay(400)
        if mq.TLO.Cursor() then
            notify("GBank", "Inventory full! Aborting script workflow.", "error")
            isRunningWorkflow   = false
            isWithdrawingPicked = false
            isDepositingPicked  = false
            workflowStep        = 0
            return false
        end
    end
    return true
end

-- Handles the Quantity Selection window if it appears for stacked items
local function handleQuantityWindow()
    if mq.TLO.Window('QuantityWnd').Open() then
        notify("GBank", "Quantity window detected. Directing slider value to max...", "info")
        mq.cmd("/notify QuantityWnd QTYW_Slider newvalue 100")
        mq.delay(150)
        mq.cmd("/notify QuantityWnd QTYW_Accept_Button leftmouseup")
        mq.delay(200)
        local timeout = os.clock() + 2.0
        while not mq.TLO.Cursor() and os.clock() < timeout do
            mq.delay(50)
        end
    end
end

-- ─── Prune Spells Engine ─────────────────────────────────────────────────────

-- Walks the open guild bank, withdraws every spell/song/skill/tome whose
-- MinCasterLevel is below PRUNE_LEVEL_CUTOFF, autoinventories each one.
-- Runs one item per main-loop tick via isPruning flag.
local function handlePruneSpells()
    if not mq.TLO.Window('GuildBankWnd').Open() then
        notify("GBank Prune", "Bank window closed. Aborting prune.", "error")
        isPruning = false
        return
    end
    if os.clock() * 1000 < lastActionTime + ACTION_DELAY then return end
    if not clearCursorFailsafe() then
        isPruning = false
        return
    end

    local itemsCount = mq.TLO.Window('GuildBankWnd').Child('GBANK_ItemList').Items() or 0
    if itemsCount == 0 then
        notify("GBank Prune", "Bank list empty. Prune complete.", "success")
        isPruning = false
        return
    end

    for i = 1, itemsCount do
        local itemText = mq.TLO.Window('GuildBankWnd').Child('GBANK_ItemList').List(i, 2)()
        if itemText and itemText ~= "" and isSpellItem(itemText) then
            -- Derive spell name and look up MinCasterLevel
            local spellName = itemText
                :gsub("^%s*(.-)%s*$", "%1")
                :gsub("^[Ss]pell:%s*", "")
                :gsub("^[Ss]ong:%s*", "")
                :gsub("^[Tt]ome[: ]of%s*", "")
                :gsub("^[Tt]ome:%s*", "")
                :gsub("^[Ss]kill:%s*", "")
            local spellLevel = 0
            -- Primary: look up by stripped spell name via Spell TLO
            local ok, result = pcall(function()
                local spell = mq.TLO.Spell(spellName)
                if spell and spell() then
                    return spell.MinCasterLevel() or 0
                end
                return 0
            end)
            if ok and result and result > 0 then spellLevel = result end

            -- Fallback: use Scroll.SpellID from FindItem if the name lookup failed.
            -- FindItem won't find bank items, but for spells whose name resolves
            -- via Spell TLO this is already handled above.
            if spellLevel == 0 then
                local ok2, result2 = pcall(function()
                    local spell = mq.TLO.Spell(itemText)
                    if spell and spell() then
                        return spell.MinCasterLevel() or 0
                    end
                    return 0
                end)
                if ok2 and result2 and result2 > 0 then spellLevel = result2 end
            end

            if spellLevel > 0 and spellLevel < PRUNE_LEVEL_CUTOFF then
                notify("GBank Prune", "Withdrawing " .. hilite(itemText) .. " (level " .. hilite(spellLevel) .. " < " .. hilite(PRUNE_LEVEL_CUTOFF) .. ")...", "action")
                mq.cmd(string.format("/notify GuildBankWnd GBANK_ItemList listselect %d", i))
                mq.delay(200)
                mq.cmd("/notify GuildBankWnd GBANK_WithdrawButton leftmouseup")
                mq.delay(300)
                handleQuantityWindow()
                lastActionTime = os.clock() * 1000
                mq.delay(400)
                if mq.TLO.Cursor() then
                    if pruneAction == 2 then
                        mq.cmd("/destroy")
                        notify("GBank Prune", "Destroyed.", "warn")
                    else
                        mq.cmd("/autoinventory")
                    end
                    mq.delay(300)
                end
                return -- yield to main loop; re-scan on next tick
            elseif spellLevel == 0 then
                notify("GBank Prune", "Skipping " .. hilite(itemText) .. " (could not determine level).", "warn")
            end
        end
    end

    -- No more qualifying items found
    notify("GBank Prune", "Prune complete. No more spells below level " .. hilite(PRUNE_LEVEL_CUTOFF) .. " in bank.", "success")
    isPruning = false
end

-- ─── Bank Scan Core ───────────────────────────────────────────────────────────

-- Internal: walks GBANK_ItemList or inventory, calls matchFn(itemName) for each row,
-- populates scanResults / selectedForWithdrawal, sets picker metadata,
-- and opens the picker if at least one match is found.
-- Does NOT touch or move any items.
local function doScan(matchFn, windowTitle, actionLabel, mode, logTag)
    scanResults           = {}
    selectedForWithdrawal = {}
    selectedQty           = {}
    pickerWindowTitle     = windowTitle
    pickerActionLabel     = actionLabel
    pickerMode            = mode

    if not mq.TLO.Window('GuildBankWnd').Open() then
        notify(logTag, "Guild Bank window is not open. Cannot scan.", "error")
        return
    end

    local itemsCount = mq.TLO.Window('GuildBankWnd').Child('GBANK_ItemList').Items() or 0
    notify(logTag, "Scanning " .. hilite(itemsCount) .. " bank slot(s)...", "scan")

    for i = 1, itemsCount do
        local itemText = mq.TLO.Window('GuildBankWnd').Child('GBANK_ItemList').List(i, 2)()
        if itemText and itemText ~= "" then
            if matchFn(itemText) then
                local cleanName = itemText:gsub("^%s*(.-)%s*$", "%1")
                -- Read stack count from column 3 (defaults to 1 if blank/nil)
                local stackStr  = mq.TLO.Window('GuildBankWnd').Child('GBANK_ItemList').List(i, 3)()
                local stackSize = tonumber(stackStr) or 1
                -- Group stacks of the same name into one entry
                local grouped = false
                for _, entry in ipairs(scanResults) do
                    if entry.name == cleanName then
                        table.insert(entry.slots, i)
                        entry.qty = (entry.qty or 0) + stackSize
                        grouped = true
                        break
                    end
                end
                if not grouped then
                    local lvl = 0
                    -- Bank items can't be found via FindItem (not in inventory).
                    -- Instead derive the spell name from the item name prefix and
                    -- look it up directly via the Spell TLO, which works by name.
                    local spellName = cleanName
                        :gsub("^[Ss]pell:%s*", "")
                        :gsub("^[Ss]ong:%s*", "")
                        :gsub("^[Tt]ome[: ]of%s*", "")
                        :gsub("^[Tt]ome:%s*", "")
                        :gsub("^[Ss]kill:%s*", "")
                    local ok, result = pcall(function()
                        local spell = mq.TLO.Spell(spellName)
                        if spell and spell() then
                            return spell.MinCasterLevel() or 0
                        end
                        return 0
                    end)
                    if ok and result and result > 0 then lvl = result end
                    local matInfo  = anguishMatInfo[cleanName] or {}
                    table.insert(scanResults, { name = cleanName, slots = { i }, qty = stackSize, level = lvl, class = matInfo.armor or "", slot = matInfo.slot or "" })
                    selectedForWithdrawal[cleanName] = false -- unchecked by default
                    selectedQty[cleanName]           = stackSize -- default: take all
                end
            end
        end
    end

    local found = #scanResults
    notify(logTag, "Scan complete. " .. hilite(found) .. " unique matching item(s) found.", "success")

    if found > 0 then
        showPickerWindow = true
    else
        notify(logTag, "No matching items found in the bank.", "warn")
        showPickerWindow = false
    end
end

-- Public scan entry points — bank-side (GET mode)
local function scanBankAnguish()
    doScan(isAnguishMatItem,
           "Anguish Mats - Select Items to Withdraw",
           "Withdraw Selected",
           "withdraw",
           "GBank Scan: Anguish")
end

local function scanBankSpells()
    doScan(isSpellItem,
           "Spells / Songs / Skills / Tomes - Select Items to Withdraw",
           "Withdraw Selected",
           "withdraw",
           "GBank Scan: Spells")
end

-- Dispatch to the correct scanner for the active category
local function scanBankForCategory()
    if selectedCategory == 1 then
        scanBankAnguish()
    else
        scanBankSpells()
    end
end

-- Inventory scan: walks all bag slots via FindItemIter, runs isSpellItem on each,
-- populates scanResults for the deposit picker. Does NOT touch or move any items.
local function scanInventorySpells()
    scanResults           = {}
    selectedForWithdrawal = {}
    selectedQty           = {}
    pickerWindowTitle     = "Spells / Songs / Skills / Tomes - Select Items to Deposit"
    pickerActionLabel     = "Deposit Selected"
    pickerMode            = "deposit"

    notify("GBank Scan", "Scanning inventory bags for spells/songs/skills/tomes...", "scan")

    -- EQ bag slots: 23–32 are the main pack slots (up to 10 bags).
    -- Each bag can hold up to 10 items (sub-slots 1–10).
    -- mq.TLO.Me.Inventory(slotName) and FindItem work for named lookups;
    -- for a full sweep we iterate pack slots directly.
    local found = 0
    for bag = 23, 32 do
        local container = mq.TLO.InvSlot(bag).Item
        if container and container() then
            local bagSize = container.Container() or 0
            for slot = 1, bagSize do
                local item = container.Item(slot)
                if item and item() then
                    local itemName = item.Name()
                    if itemName and isSpellItem(itemName) then
                        local cleanName = itemName:gsub("^%s*(.-)%s*$", "%1")
                        local stackSize = item.Stack() or 1
                        -- Group duplicates (shouldn't occur in bags but be safe)
                        local grouped = false
                        for _, entry in ipairs(scanResults) do
                            if entry.name == cleanName then
                                table.insert(entry.slots, string.format("bag%d-slot%d", bag, slot))
                                entry.qty = (entry.qty or 0) + stackSize
                                grouped = true
                                break
                            end
                        end
                        if not grouped then
                            local lvl = 0
                            local itemTLO = mq.TLO.FindItem(string.format("=%s", cleanName))
                            if itemTLO and itemTLO() then
                                local ok, result = pcall(function()
                                    local spellID = itemTLO.Scroll.SpellID()
                                    if spellID and spellID > 0 then
                                        local spell = mq.TLO.Spell(spellID)
                                        if spell and spell() then
                                            return spell.MinCasterLevel() or 0
                                        end
                                    end
                                    return 0
                                end)
                                if ok and result and result > 0 then lvl = result end
                            end
                            table.insert(scanResults, {
                                name  = cleanName,
                                slots = { string.format("bag%d-slot%d", bag, slot) },
                                qty   = stackSize,
                                level = lvl
                            })
                            selectedForWithdrawal[cleanName] = false
                            selectedQty[cleanName]           = stackSize
                            found = found + 1
                        end
                    end
                end
            end
        end
    end

    notify("GBank Scan", "Scan complete. " .. hilite(#scanResults) .. " unique matching item(s) found.", "success")

    if #scanResults > 0 then
        showPickerWindow = true
    else
        notify("GBank Scan", "No matching spell/skill/song/tome items found in inventory.", "warn")
        showPickerWindow = false
    end
end

-- Inventory scan: Anguish Mats — walks bags, matches against itemTargetList
local function scanInventoryAnguish()
    scanResults           = {}
    selectedForWithdrawal = {}
    selectedQty           = {}
    pickerWindowTitle     = "Anguish Mats - Select Items to Deposit"
    pickerActionLabel     = "Deposit Selected"
    pickerMode            = "deposit"

    notify("GBank Scan", "Scanning inventory bags for Anguish Mats...", "scan")

    for bag = 23, 32 do
        local container = mq.TLO.InvSlot(bag).Item
        if container and container() then
            local bagSize = container.Container() or 0
            for slot = 1, bagSize do
                local item = container.Item(slot)
                if item and item() then
                    local itemName = item.Name()
                    if itemName and isAnguishMatItem(itemName) then
                        local cleanName = itemName:gsub("^%s*(.-)%s*$", "%1")
                        local stackSize = item.Stack() or 1
                        local grouped = false
                        for _, entry in ipairs(scanResults) do
                            if entry.name == cleanName then
                                table.insert(entry.slots, string.format("bag%d-slot%d", bag, slot))
                                entry.qty = (entry.qty or 0) + stackSize
                                grouped = true
                                break
                            end
                        end
                        if not grouped then
                            local matInfo  = anguishMatInfo[cleanName] or {}
                            table.insert(scanResults, {
                                name  = cleanName,
                                slots = { string.format("bag%d-slot%d", bag, slot) },
                                qty   = stackSize,
                                level = 0,
                                class = matInfo.armor or "",
                                slot  = matInfo.slot  or "",
                            })
                            selectedForWithdrawal[cleanName] = false
                            selectedQty[cleanName]           = stackSize
                        end
                    end
                end
            end
        end
    end

    notify("GBank Scan", "Scan complete. " .. hilite(#scanResults) .. " unique matching item(s) found.", "success")

    if #scanResults > 0 then
        showPickerWindow = true
    else
        notify("GBank Scan", "No matching Anguish Mat items found in inventory.", "warn")
        showPickerWindow = false
    end
end

-- Dispatch inventory scan to the correct function for the active category
local function scanInventoryForCategory()
    if selectedCategory == 1 then
        scanInventoryAnguish()
    else
        scanInventorySpells()
    end
end



-- Withdraws items listed in withdrawQueue one name per main-loop tick.
-- Re-scans slot indices live after each action so shifts never cause misses.
local function handlePickedWithdrawal()
    if not mq.TLO.Window('GuildBankWnd').Open() then
        notify("GBank Withdraw", "Bank window closed. Aborting selected withdrawal.", "error")
        isWithdrawingPicked = false
        withdrawQueue       = {}
        return
    end
    if os.clock() * 1000 < lastActionTime + ACTION_DELAY then return end
    if not clearCursorFailsafe() then
        isWithdrawingPicked = false
        withdrawQueue       = {}
        return
    end

    while #withdrawQueue > 0 do
        local entry      = withdrawQueue[1]
        local targetName = type(entry) == "table" and entry.name or entry
        local wantQty    = type(entry) == "table" and (entry.qty or 1) or 1

        -- Re-scan live slot list (indices shift after each withdrawal)
        local itemsCount = mq.TLO.Window('GuildBankWnd').Child('GBANK_ItemList').Items() or 0
        local foundSlot  = nil
        for i = 1, itemsCount do
            local txt = mq.TLO.Window('GuildBankWnd').Child('GBANK_ItemList').List(i, 2)()
            if txt then
                local clean = txt:gsub("^%s*(.-)%s*$", "%1")
                if clean == targetName then foundSlot = i break end
            end
        end

        if foundSlot then
            -- Read current stack size so we know how much this pull takes
            local stackStr  = mq.TLO.Window('GuildBankWnd').Child('GBANK_ItemList').List(foundSlot, 3)()
            local stackSize = tonumber(stackStr) or 1

            notify("GBank Withdraw", "Withdrawing " .. hilite(targetName) ..
                " from slot " .. hilite(foundSlot) ..
                " (want " .. hilite(wantQty) .. ", stack " .. hilite(stackSize) .. ")...", "action")
            mq.cmd(string.format("/notify GuildBankWnd GBANK_ItemList listselect %d", foundSlot))
            mq.delay(200)
            mq.cmd("/notify GuildBankWnd GBANK_WithdrawButton leftmouseup")
            mq.delay(300)

            -- For partial-stack withdrawals: if the stack is larger than needed,
            -- the QuantityWnd will appear — set it to wantQty instead of max.
            if mq.TLO.Window('QuantityWnd').Open() then
                if wantQty >= stackSize then
                    -- Take the whole stack (or all we still need)
                    notify("GBank", "Quantity window: taking full stack (" .. hilite(stackSize) .. ").", "info")
                    mq.cmd("/notify QuantityWnd QTYW_Slider newvalue 100")
                else
                    -- Take only as many as requested
                    notify("GBank", "Quantity window: setting to " .. hilite(wantQty) .. ".", "info")
                    mq.cmd(string.format("/notify QuantityWnd QTYW_Slider newvalue %d", wantQty))
                end
                mq.delay(150)
                mq.cmd("/notify QuantityWnd QTYW_Accept_Button leftmouseup")
                mq.delay(200)
                local timeout = os.clock() + 2.0
                while not mq.TLO.Cursor() and os.clock() < timeout do mq.delay(50) end
            else
                handleQuantityWindow()
            end

            lastActionTime = os.clock() * 1000
            mq.delay(400)

            if mq.TLO.Cursor() then
                mq.cmd("/autoinventory")
                mq.delay(300)
            end

            -- Subtract what we just pulled from the remaining want-qty.
            -- If satisfied (or the item is gone from the bank), advance the queue.
            local pulled = math.min(wantQty, stackSize)
            local remaining = wantQty - pulled

            if remaining <= 0 then
                table.remove(withdrawQueue, 1)
            else
                -- Still need more — update the qty on the queue entry and loop
                if type(withdrawQueue[1]) == "table" then
                    withdrawQueue[1].qty = remaining
                end
                -- Check the item is still in the bank before looping
                local stillPresent = false
                local countAfter = mq.TLO.Window('GuildBankWnd').Child('GBANK_ItemList').Items() or 0
                for i = 1, countAfter do
                    local txt = mq.TLO.Window('GuildBankWnd').Child('GBANK_ItemList').List(i, 2)()
                    if txt then
                        local clean = txt:gsub("^%s*(.-)%s*$", "%1")
                        if clean == targetName then stillPresent = true break end
                    end
                end
                if not stillPresent then
                    notify("GBank Withdraw", hilite(targetName) .. " depleted in bank before qty satisfied. Advancing.", "warn")
                    table.remove(withdrawQueue, 1)
                end
            end
            return -- yield to main loop for throttle / cursor safety
        else
            notify("GBank Withdraw", hilite(targetName) .. " not found in bank. Skipping.", "warn")
            table.remove(withdrawQueue, 1)
        end
    end

    -- Queue exhausted
    notify("GBank Withdraw", "All selected items withdrawn successfully.", "success")
    isWithdrawingPicked   = false
    showPickerWindow      = false
    scanResults           = {}
    selectedForWithdrawal = {}
end

-- ─── Standard Full-Sweep GET (Spells GIVE fallback / non-picker paths) ────────

local function handleGetMode()
    if not isRunningWorkflow then return end
    if not mq.TLO.Window('GuildBankWnd').Open() then return end
    if os.clock() * 1000 < lastActionTime + ACTION_DELAY then return end
    if not clearCursorFailsafe() then return end

    local itemsCount = mq.TLO.Window('GuildBankWnd').Child('GBANK_ItemList').Items() or 0
    if itemsCount == 0 then return end

    for i = 1, itemsCount do
        if not isRunningWorkflow then return end
        local itemText = mq.TLO.Window('GuildBankWnd').Child('GBANK_ItemList').List(i, 2)()
        if itemText and itemText ~= "" then
            if isTargetItem(itemText) then
                notify("GBank GET", "Match: " .. hilite(itemText) .. " in slot " .. hilite(i) .. ".", "success")
                mq.delay(100)
                mq.cmd(string.format("/notify GuildBankWnd GBANK_ItemList listselect %d", i))
                mq.delay(200)
                mq.cmd("/notify GuildBankWnd GBANK_WithdrawButton leftmouseup")
                mq.delay(300)
                handleQuantityWindow()
                lastActionTime = os.clock() * 1000
                mq.delay(400)
                if mq.TLO.Cursor() then mq.cmd("/autoinventory") end
                return
            end
        end
    end

    if isRunningWorkflow then
        notify("GBank GET", "No more matching items on this page.", "warn")
        isRunningWorkflow = false
        workflowStep      = 0
    end
end

-- ─── Merge Stacks Engine ────────────────────────────────────────────

local function handleMergeStacks()
    if not mq.TLO.Window('GuildBankWnd').Open() then
        notify("GBank Merge", "Bank window closed. Aborting.", "error")
        isMerging = false
        return
    end
    notify("GBank Merge", "Merging stacks for all items in vault...", "officer")
    local count = mq.TLO.Window('GuildBankWnd').Child('GBANK_ItemList').Items() or 0
    for i = 1, count do
        if not isMerging then return end
        if not mq.TLO.Window('GuildBankWnd').Open() then
            notify("GBank Merge", "Bank window closed mid-sweep. Aborting.", "error")
            isMerging = false
            return
        end
        local txt = mq.TLO.Window('GuildBankWnd').Child('GBANK_ItemList').List(i, 2)()
        local qtyStr = mq.TLO.Window('GuildBankWnd').Child('GBANK_ItemList').List(i, 3)()
        local qty = tonumber(qtyStr) or 0
        if txt and txt ~= "" and qty > 0 then
            mq.cmd(string.format("/notify GuildBankWnd GBANK_ItemList listselect %d", i))
            mq.delay(200)
            mq.cmd("/notify GuildBankWnd GBANK_MergeButton leftmouseup")
            mq.delay(400)
        end
    end
    notify("GBank Merge", "Stack merge complete.", "success")
    isMerging = false
end

-- ─── GIVE Mode ────────────────────────────────────────────────────────────────

-- Method A: promote deposit staging items to vault and set all to Public
local function processOfficerPublicVaultRoutines()
    if not isRunningWorkflow then return end
    if not mq.TLO.Window('GuildBankWnd').Open() then return end

    notify("GBank Give", "GIVE complete. Checking deposit staging list...", "info")
    mq.delay(500)

    local depositCount = mq.TLO.Window('GuildBankWnd').Child('GBANK_DepositList').Items() or 0
    while depositCount > 0 and isRunningWorkflow do
        notify("GBank Give", "Promoting deposit slot 1... (" .. hilite(depositCount) .. " remaining)", "action")
        mq.cmd("/notify GuildBankWnd GBANK_DepositList listselect 1")
        mq.delay(250)
        mq.cmd("/notify GuildBankWnd GBANK_PromoteButton leftmouseup")
        mq.delay(600)
        depositCount = mq.TLO.Window('GuildBankWnd').Child('GBANK_DepositList').Items() or 0
    end

    notify("GBank Promote", "Performing public-access sweep across all vault slots...", "officer")
    mq.delay(500)

    local mainItemsCount = mq.TLO.Window('GuildBankWnd').Child('GBANK_ItemList').Items() or 0
    if mainItemsCount == 0 then return end

    for i = 1, mainItemsCount do
        if not isRunningWorkflow then return end
        local itemText = mq.TLO.Window('GuildBankWnd').Child('GBANK_ItemList').List(i, 2)()
        if itemText and itemText ~= "" then
            local permText = mq.TLO.Window('GuildBankWnd').Child('GBANK_ItemList').List(i, 4)() or ""
            if permText:lower() ~= "public" then
                notify("GBank Promote", "Row " .. hilite(i) .. " (" .. hilite(itemText) .. ") permission=" .. hilite(permText) .. ". Forcing PUBLIC...", "officer")
                mq.cmd(string.format("/notify GuildBankWnd GBANK_ItemList listselect %d", i))
                mq.delay(250)
                mq.cmd("/notify GuildBankWnd GBANK_PermissionCombo listselect 4")
                mq.delay(500)
            end
        end
    end

    -- Merge stacks across all vault items
    local mergeCount = mq.TLO.Window('GuildBankWnd').Child('GBANK_ItemList').Items() or 0
    if mergeCount > 0 then
        notify("GBank Promote", "Merging stacks for all items in vault...", "officer")
        mq.delay(300)
        for i = 1, mergeCount do
            if not isRunningWorkflow then return end
            if not mq.TLO.Window('GuildBankWnd').Open() then return end
            local txt = mq.TLO.Window('GuildBankWnd').Child('GBANK_ItemList').List(i, 2)()
            local qtyStr = mq.TLO.Window('GuildBankWnd').Child('GBANK_ItemList').List(i, 3)()
            local qty = tonumber(qtyStr) or 0
            if txt and txt ~= "" and qty > 0 then
                mq.cmd(string.format("/notify GuildBankWnd GBANK_ItemList listselect %d", i))
                mq.delay(200)
                mq.cmd("/notify GuildBankWnd GBANK_MergeButton leftmouseup")
                mq.delay(400)
            end
        end
    end

    notify("GBank Promote", "Transfer, public-sweep, and stack merge finished successfully!", "success")
end

-- ─── Picked Deposit Engine ────────────────────────────────────────────────────

-- Deposits items listed in depositQueue one name per main-loop tick.
-- Uses FindItem to locate the item in bags, picks it up, then deposits it.
local function handlePickedDeposit()
    if not mq.TLO.Window('GuildBankWnd').Open() then
        notify("GBank Deposit", "Bank window closed. Aborting selected deposit.", "error")
        isDepositingPicked = false
        depositQueue       = {}
        return
    end
    if os.clock() * 1000 < lastActionTime + ACTION_DELAY then return end
    if not clearCursorFailsafe() then
        isDepositingPicked = false
        depositQueue       = {}
        return
    end

    if #depositQueue > 0 then
        local entry      = depositQueue[1]
        local targetName = type(entry) == "table" and entry.name or entry
        local wantQty    = type(entry) == "table" and (entry.qty or 1) or 1
        local item = mq.TLO.FindItem(string.format("=%s", targetName))

        if item and item() then
            notify("GBank Deposit", "Depositing " .. hilite(targetName) ..
                " (want " .. hilite(wantQty) .. ")...", "action")
            mq.cmd(string.format("/shift /itemnotify \"%s\" leftmouseup", targetName))
            mq.delay(400)

            if mq.TLO.Cursor() then
                mq.cmd("/notify GuildBankWnd GBANK_DepositButton leftmouseup")
                lastActionTime = os.clock() * 1000
                mq.delay(400)
            end

            -- Decrement wantQty by 1 (we deposit one stack/item per tick).
            -- Advance queue when satisfied or when no more of this item exist in inventory.
            local newWant = wantQty - 1
            local still   = mq.TLO.FindItem(string.format("=%s", targetName))
            if newWant <= 0 or not (still and still()) then
                table.remove(depositQueue, 1)
            else
                if type(depositQueue[1]) == "table" then
                    depositQueue[1].qty = newWant
                end
            end
        else
            notify("GBank Deposit", hilite(targetName) .. " not found in inventory. Skipping.", "warn")
            table.remove(depositQueue, 1)
        end
        return -- yield to main loop
    end

    -- Queue exhausted — run public-vault sweep then clean up
    if cachedIsOfficer then
        notify("GBank Deposit", "All selected items deposited. Running public-access sweep...", "success")
        isRunningWorkflow = true
        processOfficerPublicVaultRoutines()
        isRunningWorkflow = false
    else
        notify("GBank Deposit", "All selected items deposited. Skipping public-access sweep (not an officer).", "warn")
    end
    isDepositingPicked = false
    showPickerWindow   = false
    scanResults           = {}
    selectedForWithdrawal = {}
    notify("GBank Deposit", "Deposit complete.", "success")
end


local function handleGiveMode()
    if not isRunningWorkflow then return end
    if not mq.TLO.Window('GuildBankWnd').Open() then return end
    if os.clock() * 1000 < lastActionTime + ACTION_DELAY then return end
    if not clearCursorFailsafe() then return end

    for _, name in ipairs(activeList()) do
        if not isRunningWorkflow then return end
        local item = mq.TLO.FindItem(string.format("=%s", name))
        if item and item() then
            notify("GBank Give", "Match: " .. hilite(name) .. " in inventory.", "success")
            mq.delay(100)
            mq.cmd(string.format("/shift /itemnotify \"%s\" leftmouseup", name))
            mq.delay(400)
            if mq.TLO.Cursor() then
                mq.cmd("/notify GuildBankWnd GBANK_DepositButton leftmouseup")
                lastActionTime = os.clock() * 1000
                mq.delay(400)
                return
            end
        end
    end

    if isRunningWorkflow then
        if cachedIsOfficer then
            processOfficerPublicVaultRoutines()
        else
            notify("GBank Give", "Skipping public-access sweep (not an officer).", "warn")
        end
        isRunningWorkflow = false
        workflowStep      = 0
    end
end

-- ─── Navigation Workflow ──────────────────────────────────────────────────────

-- True when the current mode uses the picker-scan path (both categories in GET mode)
local function isPickerGetMode()
    return selectedOption == 1 -- GET mode always uses picker for both categories
end

local function processBankWorkflow()
    if workflowStep == 1 then
        mq.cmd("/target npc \"guild treasurer\"")
        mq.delay(300)
        local targetName = mq.TLO.Target.CleanName()
        if targetName and string.find(targetName:lower(), "guild treasurer") then
            notify("GBank Workflow", "Target found: " .. targetName .. ". Navigating...", "info")
            mq.cmd("/nav target")
            workflowStep = 2
        else
            notify("GBank Workflow", "Error: Could not locate a Guild Treasurer nearby.", "error")
            isRunningWorkflow = false
            workflowStep      = 0
        end
        return
    end

    if workflowStep == 2 then
        if not mq.TLO.Navigation.Active() then
            local dist = mq.TLO.Target.Distance()
            if dist and dist < 20 then
                notify("GBank Workflow", "Arrived. Interacting...", "info")
                mq.cmd("/click left target")
                mq.delay(1000)
                workflowStep = 3
            else
                notify("GBank Workflow", "Navigation failed or stopped short. Aborting.", "error")
                isRunningWorkflow = false
                workflowStep      = 0
            end
        end
        return
    end

    if workflowStep == 3 then
        if mq.TLO.Window('GuildBankWnd').Open() then
            notify("GBank Workflow", "Bank open. Starting...", "success")
            workflowStep = 4
        else
            mq.cmd("/click right target")
            mq.delay(1000)
        end
        return
    end

    if workflowStep == 4 then
        if not mq.TLO.Window('GuildBankWnd').Open() then
            notify("GBank Workflow", "Bank window closed. Aborting.", "error")
            isRunningWorkflow = false
            pendingPrune      = false
            pendingPromote    = false
            pendingMerge      = false
            workflowStep      = 0
            return
        end

        if pendingPrune then
            pendingPrune      = false
            isRunningWorkflow = false
            workflowStep      = 0
            isPruning         = true
            notify("GBank Prune", "Bank open. Starting spell prune (withdrawing spells below level " .. hilite(PRUNE_LEVEL_CUTOFF) .. ")...", "info")
        elseif pendingPromote then
            pendingPromote    = false
            isRunningWorkflow = false
            workflowStep      = 0
            isPromoting       = true
            notify("GBank Promote", "Bank open. Starting public-access sweep...", "officer")
        elseif pendingMerge then
            pendingMerge      = false
            isRunningWorkflow = false
            workflowStep      = 0
            isMerging         = true
            notify("GBank Merge", "Bank open. Starting stack merge sweep...", "officer")
        elseif selectedOption == 1 then
            -- Both categories in GET mode: bank scan → picker
            scanBankForCategory()
            isRunningWorkflow = false
            workflowStep      = 0
        else
            -- Both categories in GIVE mode: inventory scan → picker (bank now confirmed open)
            scanInventoryForCategory()
            isRunningWorkflow = false
            workflowStep      = 0
        end
    end
end

-- ─── Picker Window ────────────────────────────────────────────────────────────

local function pickerGUI()
    if not showPickerWindow then return end

    local pickerFlags = ImGuiWindowFlags.AlwaysAutoResize
    local pVisible, pOpen = ImGui.Begin(pickerWindowTitle, true, pickerFlags)
    if pVisible then
        if #scanResults == 0 then
            ImGui.TextColored(1.0, 0.6, 0.2, 1.0, "No matching items found in the bank.")
        else
            ImGui.Text(string.format("%d matching item(s) found. Select items to %s:",
                #scanResults, pickerMode == "deposit" and "deposit" or "withdraw"))
            ImGui.Separator()

            if ImGui.Button("Select All") then
                for _, entry in ipairs(scanResults) do
                    selectedForWithdrawal[entry.name] = true
                end
            end
            ImGui.SameLine()
            if ImGui.Button("Deselect All") then
                for _, entry in ipairs(scanResults) do
                    selectedForWithdrawal[entry.name] = false
                end
            end

            ImGui.Separator()

            local showLevel  = (selectedCategory == 2) -- only spells have meaningful levels
            local showClass  = (selectedCategory == 1) -- only Anguish Mats have armor/slot columns
            local extraColW  = 130                      -- width for the Level / Armor Type columns
            local slotColW   = 70                       -- width for the Slot column
            local qtyColW    = 140                      -- width for the Qty / input column (needs room for "99 / 99 [-][+]")
            local listWidth  = showLevel  and (360 + extraColW + qtyColW)
                            or showClass  and (360 + extraColW + slotColW + qtyColW)
                            or (360 + qtyColW)
            local listHeight = math.min(#scanResults * 26 + 8, 300)

            -- Sort chevron helper: returns " [^]" / " [v]" on the active col, "" otherwise
            local function sortArrow(col)
                if pickerSortCol ~= col then return "" end
                return pickerSortAsc and " [^]" or " [v]"
            end

            -- Click a header button: toggle direction if same col, else switch col asc
            local function handleSortClick(col)
                if pickerSortCol == col then
                    pickerSortAsc = not pickerSortAsc
                else
                    pickerSortCol = col
                    pickerSortAsc = true
                end
            end

            -- Render sortable column headers (outside the scrollable child)
            if showLevel then
                ImGui.Columns(3, "PickerHdrCols", false)
                ImGui.SetColumnWidth(0, 360)
                ImGui.SetColumnWidth(1, extraColW)
                ImGui.SetColumnWidth(2, qtyColW)
                if ImGui.Button("Item" .. sortArrow("name"), ImVec2(350, 0)) then handleSortClick("name") end
                ImGui.NextColumn()
                if ImGui.Button("Req. Level" .. sortArrow("level"), ImVec2(extraColW - 8, 0)) then handleSortClick("level") end
                ImGui.NextColumn()
                ImGui.Text("Qty")
                ImGui.NextColumn()
                ImGui.Columns(1)
                ImGui.Separator()
            elseif showClass then
                ImGui.Columns(4, "PickerHdrCols", false)
                ImGui.SetColumnWidth(0, 360)
                ImGui.SetColumnWidth(1, extraColW)
                ImGui.SetColumnWidth(2, slotColW)
                ImGui.SetColumnWidth(3, qtyColW)
                if ImGui.Button("Item" .. sortArrow("name"),  ImVec2(350, 0))          then handleSortClick("name")  end
                ImGui.NextColumn()
                if ImGui.Button("Armor Type" .. sortArrow("armor"), ImVec2(extraColW - 8, 0)) then handleSortClick("armor") end
                ImGui.NextColumn()
                if ImGui.Button("Slot" .. sortArrow("slot"),  ImVec2(slotColW - 8, 0)) then handleSortClick("slot")  end
                ImGui.NextColumn()
                ImGui.Text("Qty")
                ImGui.NextColumn()
                ImGui.Columns(1)
                ImGui.Separator()
            else
                ImGui.Columns(2, "PickerHdrCols", false)
                ImGui.SetColumnWidth(0, 360)
                ImGui.SetColumnWidth(1, qtyColW)
                if ImGui.Button("Item" .. sortArrow("name"), ImVec2(350, 0)) then handleSortClick("name") end
                ImGui.NextColumn()
                ImGui.Text("Qty")
                ImGui.NextColumn()
                ImGui.Columns(1)
                ImGui.Separator()
            end

            -- Build a sorted view (shallow copy so scanResults order is preserved for queuing)
            local sorted = {}
            for _, e in ipairs(scanResults) do table.insert(sorted, e) end
            table.sort(sorted, function(a, b)
                local av, bv
                if pickerSortCol == "level" then
                    av = a.level or 0
                    bv = b.level or 0
                elseif pickerSortCol == "armor" then
                    av = (a.class or ""):lower()
                    bv = (b.class or ""):lower()
                elseif pickerSortCol == "slot" then
                    av = (a.slot or ""):lower()
                    bv = (b.slot or ""):lower()
                else -- "name"
                    av = a.name:lower()
                    bv = b.name:lower()
                end
                if av == bv then
                    -- secondary sort: always ascending by name to keep order stable
                    return a.name:lower() < b.name:lower()
                end
                if pickerSortAsc then return av < bv else return av > bv end
            end)

            ImGui.BeginChild("PickerList", listWidth, listHeight, false)

            if showLevel then
                ImGui.Columns(3, "PickerCols", false)
                ImGui.SetColumnWidth(0, 360)
                ImGui.SetColumnWidth(1, extraColW)
                ImGui.SetColumnWidth(2, qtyColW)
            elseif showClass then
                ImGui.Columns(4, "PickerCols", false)
                ImGui.SetColumnWidth(0, 360)
                ImGui.SetColumnWidth(1, extraColW)
                ImGui.SetColumnWidth(2, slotColW)
                ImGui.SetColumnWidth(3, qtyColW)
            else
                ImGui.Columns(2, "PickerCols", false)
                ImGui.SetColumnWidth(0, 360)
                ImGui.SetColumnWidth(1, qtyColW)
            end

            for _, entry in ipairs(sorted) do
                local checked    = selectedForWithdrawal[entry.name] or false
                local newChecked = ImGui.Checkbox(entry.name, checked)
                if newChecked ~= checked then
                    selectedForWithdrawal[entry.name] = newChecked
                    -- When first checked, default qty to the full available amount
                    if newChecked and (not selectedQty[entry.name] or selectedQty[entry.name] == 0) then
                        selectedQty[entry.name] = entry.qty or 1
                    end
                end
                if showLevel then
                    ImGui.NextColumn()
                    local lvlStr = (entry.level and entry.level > 0) and tostring(entry.level) or "-"
                    ImGui.Text(lvlStr)
                    ImGui.NextColumn()
                elseif showClass then
                    ImGui.NextColumn()
                    ImGui.Text((entry.class and entry.class ~= "") and entry.class or "-")
                    ImGui.NextColumn()
                    ImGui.Text((entry.slot  and entry.slot  ~= "") and entry.slot  or "-")
                    ImGui.NextColumn()
                else
                    ImGui.NextColumn()
                end
                -- Qty spinner: always shown, editable only when checked
                local totalQty = entry.qty or 1
                local curQty   = selectedQty[entry.name] or totalQty
                ImGui.Text(string.format("%d / %d", curQty, totalQty))
                if checked then
                    ImGui.SameLine()
                    ImGui.PushID("qtydown_" .. entry.name)
                    if ImGui.SmallButton("-") then
                        selectedQty[entry.name] = math.max(1, curQty - 1)
                    end
                    ImGui.PopID()
                    ImGui.SameLine()
                    ImGui.PushID("qtyup_" .. entry.name)
                    if ImGui.SmallButton("+") then
                        selectedQty[entry.name] = math.min(totalQty, curQty + 1)
                    end
                    ImGui.PopID()
                end
                ImGui.NextColumn()
            end

            ImGui.Columns(1)

            ImGui.EndChild()

            ImGui.Separator()

            local tickedCount = 0
            for _, v in pairs(selectedForWithdrawal) do
                if v then tickedCount = tickedCount + 1 end
            end

            if isWithdrawingPicked then
                ImGui.TextColored(0.0, 1.0, 0.0, 1.0, string.format("Withdrawing... (%d remaining)", #withdrawQueue))
                if ImGui.Button("CANCEL WITHDRAWAL", ImVec2(200, 25)) then
                    isWithdrawingPicked = false
                    withdrawQueue       = {}
                    notify("GBank Withdraw", "Withdrawal cancelled by user.", "warn")
                end
            elseif isDepositingPicked then
                ImGui.TextColored(0.0, 1.0, 0.0, 1.0, string.format("Depositing... (%d remaining)", #depositQueue))
                if ImGui.Button("CANCEL DEPOSIT", ImVec2(200, 25)) then
                    isDepositingPicked = false
                    depositQueue       = {}
                    notify("GBank Deposit", "Deposit cancelled by user.", "warn")
                end
            else
                if tickedCount == 0 then ImGui.BeginDisabled() end
                if ImGui.Button(string.format("%s (%d)", pickerActionLabel, tickedCount), ImVec2(210, 25)) then
                    if pickerMode == "deposit" then
                        depositQueue = {}
                        for _, entry in ipairs(scanResults) do
                            if selectedForWithdrawal[entry.name] then
                                local qty = math.max(1, math.min(selectedQty[entry.name] or entry.qty or 1, entry.qty or 1))
                                table.insert(depositQueue, { name = entry.name, qty = qty })
                            end
                        end
                        isDepositingPicked    = true
                        showPickerWindow      = false
                        scanResults           = {}
                        selectedForWithdrawal = {}
                        selectedQty           = {}
                        notify("GBank Deposit", "Queuing " .. hilite(#depositQueue) .. " item type(s) for deposit.", "info")
                    else
                        withdrawQueue = {}
                        for _, entry in ipairs(scanResults) do
                            if selectedForWithdrawal[entry.name] then
                                local qty = math.max(1, math.min(selectedQty[entry.name] or entry.qty or 1, entry.qty or 1))
                                table.insert(withdrawQueue, { name = entry.name, qty = qty })
                            end
                        end
                        isWithdrawingPicked   = true
                        showPickerWindow      = false
                        scanResults           = {}
                        selectedForWithdrawal = {}
                        selectedQty           = {}
                        notify("GBank Withdraw", "Queuing " .. hilite(#withdrawQueue) .. " item type(s) for withdrawal.", "info")
                    end
                end
                if tickedCount == 0 then ImGui.EndDisabled() end

                ImGui.SameLine()
                if ImGui.Button("Close", ImVec2(60, 25)) then
                    showPickerWindow      = false
                    scanResults           = {}
                    selectedForWithdrawal = {}
                    selectedQty           = {}
                end
            end
        end
    end
    ImGui.End()
    if not pOpen then
        showPickerWindow    = false
        isWithdrawingPicked = false
        isDepositingPicked  = false
        withdrawQueue       = {}
        depositQueue        = {}
        selectedQty         = {}
    end
end

-- ─── Guild Rank Lookup ────────────────────────────────────────────────────────

-- Opens the guild management window, finds our row, caches the rank, then closes it.
-- Must be called from the main loop thread (delays are safe there).
local function fetchGuildRank()
    local myName  = mq.TLO.Me.Name() or ""
    local wasOpen = mq.TLO.Window('GuildManagementWnd').Open()

    if not wasOpen then
        mq.TLO.Window('GuildManagementWnd').DoOpen()
        -- Wait up to 5 seconds for window to open and member list to populate
        local timeout = os.clock() + 5.0
        while os.clock() < timeout do
            mq.delay(100)
            local cnt = mq.TLO.Window('GuildManagementWnd').Child('GT_MemberList').Items()
            if mq.TLO.Window('GuildManagementWnd').Open() and cnt and cnt > 0 then break end
        end
    end

    if not mq.TLO.Window('GuildManagementWnd').Open() then
        notify("GBank", "GuildManagementWnd could not be opened. Cannot determine guild rank.", "error")
        return
    end

    local memberCount = mq.TLO.Window('GuildManagementWnd').Child('GT_MemberList').Items() or 0

    -- Find our row by scanning all columns for our name
    local myRow = nil
    for gi = 1, memberCount do
        for col = 1, 6 do
            local v = mq.TLO.Window('GuildManagementWnd').Child('GT_MemberList').List(gi, col)() or ""
            if v:lower() == myName:lower() then
                myRow = gi
                break
            end
        end
        if myRow then break end
    end

    if myRow then
        mq.cmd(string.format("/notify GuildManagementWnd GT_MemberList listselect %d", myRow))
        mq.delay(500)

        local rank = mq.TLO.Window('GuildManagementWnd').Child('GT_MemberList').List(myRow, 4)() or "Unknown"
        cachedGuildRank = rank
        local rl = rank:lower()
        cachedIsOfficer = (rl == "officer" or rl == "leader")
        notify("GBank", "Guild rank detected: " .. hilite(rank) .. " (Officer: " .. hilite(tostring(cachedIsOfficer)) .. ")", "officer")
    else
        notify("GBank", "Could not find " .. hilite(myName) .. " in " .. hilite(memberCount) .. " guild members.", "error")
    end

    if not wasOpen then
        mq.TLO.Window('GuildManagementWnd').DoClose()
    end
end

-- ─── Main GUI ─────────────────────────────────────────────────────────────────

local function mainGUI()
    if not openGUI then shouldDraw = false return end

    -- Drive collapse state from /gbmhide or /gbmshow.
    -- pendingCollapseSet is true for exactly one frame after a bind fires, so
    -- we use ImGuiCond.Always to override ImGui's stored state.  After that one
    -- frame we clear the flag and let ImGui (and the chevron) manage state freely.
    local wasBindDriven = pendingCollapseSet
    if pendingCollapseSet then
        ImGui.SetNextWindowCollapsed(windowCollapsed, ImGuiCond.Always)
        pendingCollapseSet = false
    end

    local flags = ImGuiWindowFlags.AlwaysAutoResize
    local visible, open = ImGui.Begin("Guild Bank Automator v" .. version, openGUI, flags)

    -- Sync collapse state and notify if the user toggled via the chevron.
    local prevCollapsed = windowCollapsed
    windowCollapsed = ImGui.IsWindowCollapsed()
    if not wasBindDriven and windowCollapsed ~= prevCollapsed then
        if windowCollapsed then
            notify("GBank", "Main window minimized. Type " .. hilite("/gbmshow") .. " to restore it.", "info")
        else
            notify("GBank", "Main window restored. Type " .. hilite("/gbmhide") .. " to minimize it.", "success")
        end
    end
    if visible then
        -- Guild rank / officer status (cached at startup)
        if cachedIsOfficer then
            ImGui.TextColored(0.2, 1.0, 0.4, 1.0, string.format("Guild Rank: %s  [Officer Access]", cachedGuildRank))
        else
            ImGui.TextColored(1.0, 0.6, 0.2, 1.0, string.format("Guild Rank: %s  [No Officer Access]", cachedGuildRank))
        end

        -- Officer-only action buttons
        if cachedIsOfficer and not (isRunningWorkflow or isWithdrawingPicked or isDepositingPicked or isPruning or isPromoting or isMerging) then
            ImGui.Separator()
            local pruneW   = 130
            local promoteW = 90
            local mergeW   = 130
            local sp       = ImGui.GetStyle().ItemSpacing.x
            local winW     = ImGui.GetWindowWidth()
            -- Row 1: PRUNE SPELLS centered
            ImGui.SetCursorPosX((winW - pruneW) * 0.5)
            if ImGui.Button("PRUNE SPELLS", ImVec2(pruneW, 25)) then
                if mq.TLO.Window('GuildBankWnd').Open() then
                    isPruning = true
                    notify("GBank Prune", "Starting spell prune (withdrawing spells below level " .. hilite(PRUNE_LEVEL_CUTOFF) .. ")...", "info")
                else
                    isPruning         = false
                    isRunningWorkflow = true
                    workflowStep      = 1
                    pendingPrune      = true
                end
            end
            -- Prune action selection
            ImGui.Text("Prune action:")
            ImGui.SameLine()
            if ImGui.RadioButton("Keep (autoinv)", pruneAction == 1) then pruneAction = 1 end
            ImGui.SameLine()
            if ImGui.RadioButton("Destroy", pruneAction == 2) then pruneAction = 2 end
            -- Row 2: MERGE STACKS + PROMOTE centered
            ImGui.Separator()
            local row2W    = promoteW + sp + mergeW
            ImGui.SetCursorPosX((winW - row2W) * 0.5)
            if ImGui.Button("PROMOTE", ImVec2(promoteW, 25)) then
                if mq.TLO.Window('GuildBankWnd').Open() then
                    isPromoting = true
                    notify("GBank Promote", "Starting public-access sweep...", "officer")
                else
                    isRunningWorkflow = true
                    workflowStep      = 1
                    pendingPromote    = true
                end
            end
            ImGui.SameLine()
            if ImGui.Button("MERGE STACKS", ImVec2(mergeW, 25)) then
                if mq.TLO.Window('GuildBankWnd').Open() then
                    isMerging = true
                    notify("GBank Merge", "Starting stack merge sweep...", "officer")
                else
                    isRunningWorkflow = true
                    workflowStep      = 1
                    pendingMerge      = true
                end
            end
        end

        ImGui.Separator()

        -- Category (locked while busy)
        ImGui.Text("Select Category:")
        if isRunningWorkflow or isWithdrawingPicked or isDepositingPicked or isPruning then ImGui.BeginDisabled() end
        if ImGui.RadioButton("Anguish Mats", selectedCategory == 1) then selectedCategory = 1 end
        if ImGui.RadioButton("Spells/Songs/Skills/Tomes", selectedCategory == 2) then selectedCategory = 2 end
        if isRunningWorkflow or isWithdrawingPicked or isDepositingPicked or isPruning then ImGui.EndDisabled() end

        ImGui.Separator()

        ImGui.Text("Select Mode:")
        if ImGui.RadioButton("GET (Withdraw)", selectedOption == 1) then selectedOption = 1 end
        if ImGui.RadioButton("GIVE (Deposit)", selectedOption == 2) then selectedOption = 2 end

        ImGui.Separator()

        local isBusy = isRunningWorkflow or isWithdrawingPicked or isDepositingPicked or isPruning or isPromoting or isMerging

        if isBusy then
            local label = isWithdrawingPicked and "CANCEL WITHDRAWAL"
                       or isDepositingPicked  and "CANCEL DEPOSIT"
                       or isPruning           and "CANCEL PRUNE"
                       or isPromoting         and "CANCEL PROMOTE"
                       or isMerging           and "CANCEL MERGE"
                       or                        "CANCEL ACTION"
            local cancelW = 180
            ImGui.SetCursorPosX(ImGui.GetCursorPosX() + (ImGui.GetContentRegionAvail() - cancelW) * 0.5)
            if ImGui.Button(label, ImVec2(cancelW, 25)) then
                mq.cmd("/nav stop")
                isRunningWorkflow  = false
                isWithdrawingPicked = false
                isDepositingPicked  = false
                isPruning          = false
                isPromoting        = false
                isMerging          = false
                pendingPrune       = false
                pendingPromote     = false
                pendingMerge       = false
                withdrawQueue      = {}
                depositQueue       = {}
                workflowStep       = 0
                notify("GBank", "Automation cancelled by user.", "warn")
            end
        else
            -- Button label depends on category + mode combination:
            --   GET (either category)        -> SCAN BANK
            --   GIVE (either category)       -> SCAN INVENTORY
            local btnLabel  = selectedOption == 1 and "SCAN GUILD BANK" or "SCAN INVENTORY"
            local btnWidth  = 180
            local availW    = ImGui.GetContentRegionAvail()
            ImGui.SetCursorPosX(ImGui.GetCursorPosX() + (availW - btnWidth) * 0.5)
            if ImGui.Button(btnLabel, ImVec2(btnWidth, 25)) then
                if selectedOption == 1 then
                    -- GET: both categories use bank picker
                    if mq.TLO.Window('GuildBankWnd').Open() then
                        scanBankForCategory()
                    else
                        isRunningWorkflow = true
                        workflowStep      = 1
                    end
                else
                    -- GIVE: both categories use inventory picker
                    -- Bank must be open to deposit afterwards
                    if mq.TLO.Window('GuildBankWnd').Open() then
                        scanInventoryForCategory()
                    else
                        -- Navigate to treasurer first, inventory scan happens at step 4
                        isRunningWorkflow = true
                        workflowStep      = 1
                    end
                end
            end
        end

        ImGui.Separator()

        if mq.TLO.Window('GuildBankWnd').Open() then
            if isWithdrawingPicked then
                ImGui.TextColored(0.0, 1.0, 0.0, 1.0, "Status: Withdrawing Selected Items...")
            elseif isDepositingPicked then
                ImGui.TextColored(0.0, 1.0, 0.0, 1.0, "Status: Depositing Selected Items...")
            elseif isPruning then
                ImGui.TextColored(1.0, 0.6, 0.0, 1.0, string.format("Status: Pruning spells below level %d...", PRUNE_LEVEL_CUTOFF))
            elseif isPromoting then
                ImGui.TextColored(0.6, 0.8, 1.0, 1.0, "Status: Running public-access sweep...")
            elseif isRunningWorkflow then
                ImGui.TextColored(0.0, 1.0, 0.0, 1.0, "Status: Transferring Items...")
            else
                ImGui.TextColored(0.0, 1.0, 1.0, 1.0, "Status: Bank Open (Paused/Idle)")
            end
        elseif isRunningWorkflow then
            ImGui.TextColored(1.0, 1.0, 0.0, 1.0, string.format("Status: Moving/Interacting (Step %d)", workflowStep))
        else
            ImGui.TextColored(1.0, 0.4, 0.4, 1.0, "Status: Idle")
        end

        ImGui.Separator()
        local exitBtnWidth = 180
        local windowWidth  = ImGui.GetContentRegionAvail()
        ImGui.SetCursorPosX(ImGui.GetCursorPosX() + (windowWidth - exitBtnWidth) * 0.5)
        ImGui.PushStyleColor(ImGuiCol.Button,        0.6, 0.1, 0.1, 1.0)
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.8, 0.2, 0.2, 1.0)
        ImGui.PushStyleColor(ImGuiCol.ButtonActive,  0.4, 0.05, 0.05, 1.0)
        if ImGui.Button("EXIT SCRIPT", ImVec2(exitBtnWidth, 25)) then
            mq.cmd("/nav stop")
            isRunningWorkflow  = false
            isWithdrawingPicked = false
            isDepositingPicked  = false
            isPruning          = false
            isPromoting        = false
            isMerging          = false
            pendingPrune       = false
            pendingPromote     = false
            pendingMerge       = false
            -- Close guild bank window if open
            if mq.TLO.Window('GuildBankWnd').Open() then
                mq.TLO.Window('GuildBankWnd').DoClose()
                notify("GBank", "Guild bank window closed.", "action")
            end
            -- Close inventory window if open
            if mq.TLO.Window('InventoryWindow').Open() then
                mq.TLO.Window('InventoryWindow').DoClose()
                notify("GBank", "Inventory window closed.", "action")
            end
            -- Close any open bag windows (Pack1-Pack10)
            for i = 1, 10 do
                local bagWnd = 'Pack' .. i
                if mq.TLO.Window(bagWnd).Open() then
                    mq.TLO.Window(bagWnd).DoClose()
                end
            end
            shouldDraw = false
            notify("GBank", "Script safely terminated.", "success")
        end
        ImGui.PopStyleColor(3)
    end
    ImGui.End()
    -- Only kill the script when the user clicks the X button (open=false and not
    -- just collapsed — a collapsed window also returns visible=false but open stays true).
    if not open and not windowCollapsed then shouldDraw = false end

    pickerGUI()
end

mq.imgui.init('GuildBankHelperUI', mainGUI)

-- ─── Window Visibility Binds ──────────────────────────────────────────────────

-- /gbmhide  — collapses the main window exactly as clicking the chevron would.
mq.bind('/gbmhide', function()
    if windowCollapsed then
        notify("GBank", "Window is already minimized. Type " .. hilite("/gbmshow") .. " to restore it.", "warn")
        return
    end
    windowCollapsed    = true
    pendingCollapseSet = true
    notify("GBank", "Main window minimized. Type " .. hilite("/gbmshow") .. " to restore it.", "info")
end)

-- /gbmshow  — restores the main window if it was collapsed by /gbmhide or the chevron.
mq.bind('/gbmshow', function()
    if not windowCollapsed then
        notify("GBank", "Window is already visible. Type " .. hilite("/gbmhide") .. " to minimize it.", "warn")
        return
    end
    windowCollapsed    = false
    pendingCollapseSet = true
    notify("GBank", "Main window restored. Type " .. hilite("/gbmhide") .. " to minimize it.", "success")
end)

-- Fetch guild rank once on startup from the main thread (delays are safe here)
fetchGuildRank()

-- ─── Primary Execution Engine ─────────────────────────────────────────────────

while shouldDraw do
    if isWithdrawingPicked then
        handlePickedWithdrawal()
    elseif isDepositingPicked then
        handlePickedDeposit()
    elseif isPruning then
        if cachedIsOfficer then
            if mq.TLO.Window('GuildBankWnd').Open() then
                handlePruneSpells()
            else
                notify("GBank Prune", "Guild Bank is not open. Aborting prune.", "error")
                isPruning = false
            end
        else
            notify("GBank Prune", "Aborted — not an officer.", "error")
            isPruning = false
        end
    elseif isPromoting then
        if cachedIsOfficer then
            if mq.TLO.Window('GuildBankWnd').Open() then
                isRunningWorkflow = true
                processOfficerPublicVaultRoutines()
                isRunningWorkflow = false
                notify("GBank Promote", "Public-access sweep complete.", "success")
            else
                notify("GBank Promote", "Guild Bank closed before sweep could run.", "error")
            end
        else
            notify("GBank Promote", "Aborted — not an officer.", "error")
        end
        isPromoting = false
    elseif isMerging then
        if cachedIsOfficer then
            handleMergeStacks()
        else
            notify("GBank Merge", "Aborted — not an officer.", "error")
            isMerging = false
        end
    elseif isRunningWorkflow then
        processBankWorkflow()
    end
    mq.delay(50)
end

mq.imgui.destroy('GuildBankHelperUI')
