
                                        GuildBankMaint SYSTEM DOCUMENTATION

-- ------------
-- GuildBankMaint - Management Tool
-- Guild Bank Automation Script for MacroQuest (MQ Lua)
-- Save as `\GuildBankMaint\init.lua` in your MacroQuest `lua` folder.
-- Run in-game with: /lua run gbank_helper
-- =============================================================================
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
<img width="265" height="295" alt="GuildBankMaint_1" src="https://github.com/user-attachments/assets/9d40815e-4726-48c7-bd6a-aa81beed5be2" />
<br>
<img width="309" height="357" alt="GuildBankMaint_2" src="https://github.com/user-attachments/assets/09fc913e-bef5-49af-9c91-ba88613250aa" />
<br>
<img width="373" height="429" alt="GuildBankMaint_3" src="https://github.com/user-attachments/assets/d6835798-c13c-4486-9519-3ba1bf193537" />
<br>
<img width="375" height="429" alt="GuildBankMaint_4" src="https://github.com/user-attachments/assets/a5e78a0b-e614-4ae2-baac-e660792b305c" />
<br>
<img width="479" height="229" alt="GuildBankMaint_5" src="https://github.com/user-attachments/assets/e93bb1de-184d-49af-8b29-cc7ad83d79e4" />
