
                                        GuildBankMaint SYSTEM DOCUMENTATION

-- ------------
-- GuildBankMaint
-- Guild Bank Automation Script for MacroQuest (MQ Lua)
-- Save as `gbank_helper.lua` in your MacroQuest `lua` folder.
-- Run in-game with: /lua run gbank_helper
-- ------------
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
-- - Guild membership (officer rank required for PROMOTE and PRUNE SPELLS)
-- - GuildManagementWnd must be openable in-game
--
-- ------------
