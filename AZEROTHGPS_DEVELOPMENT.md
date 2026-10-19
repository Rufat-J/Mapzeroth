# AzerothGPS — development branding

AzerothGPS is a customized navigation experience built on the Mapzeroth routing engine.

## Project goals
- Preserve Mapzeroth's travel graph, zone data, route calculations, and future upstream compatibility.
- Develop a compact GPS navigator and a distinct visual identity using the existing theme system.
- Add `/agps find CharacterName` for player navigation where location data is legitimately available.
- Support opt-in addon-to-addon location sharing; never assume arbitrary characters' precise positions can be queried by name.

## Current status
The first branding pass changes only the development TOC's displayed title, notes, and attribution. The folder, Lua namespace, saved variables, and original slash commands remain unchanged to avoid breaking existing functionality.

## Planned implementation
1. Audit existing UI and slash-command registrations.
2. Add a separate AzerothGPS theme without changing Mapzeroth's existing themes.
3. Introduce `/agps` commands alongside existing commands.
4. Implement supported group-location lookup and consensual player sharing.
5. Integrate player destinations into route calculation and navigator UI.

## Upstream and attribution
Based on the Mapzeroth project by tr0tsky: https://github.com/tr0tsky0/Mapzeroth

Preserve all original copyright notices and applicable license files. Review upstream changes before merging; test Forever behavior in game.
