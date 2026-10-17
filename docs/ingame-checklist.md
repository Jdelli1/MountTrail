# In-game verification checklist

Items are added by each task; verify in game.

## Task 4: lockout and holiday data

- [ ] Run `/azt dump` while saved to instances and confirm instance IDs, difficulty IDs and boss names against Data/Lockouts.lua (entries marked `-- verify in game` first).
- [ ] Midnight mounts (2817, 2805, 2607, 2950, 3058, 3030) are `manual` because their instance IDs are unknown: once `/azt dump` shows the instance ID and encounter name, replace them with instance specs.
