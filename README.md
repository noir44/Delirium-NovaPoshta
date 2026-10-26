# Delirium Nova Poshta Van

Project Zomboid Build 42 mod: Nova Poshta delivery vans.

- Vehicle scripts: `Base.StepVan_NovaPoshta` and `Base.Van_NovaPoshta` — copies of the vanilla `StepVan` and `Van` with their own skin.
- Textures: `media/textures/Vehicles/vehicle_stepvanshell_novaposhta_{white,black}.png`, `vehicle_vanshell_novaposhta_{white,black}.png` (1024×1024, vanilla UV layout), built by `art/make_livery.ps1`.
- Two skins each, white and black (models `Vehicle_StepVan_NoRandom` / `Vehicles_Van_NoRandom`, fully opaque texture); the skin is picked at random on spawn, admins switch it with *Next skin*. The body detail hidden under the vanilla paint mask is kept as shading (`make_livery.ps1 -paint`).
- Not added to any vehicle spawn zone: spawn it through the admin vehicle menu.

## Boxes

- Items `DelNP.Box5`, `DelNP.Box10`, `DelNP.Box25`: cardboard containers with capacity 5, 10 and 25.
- Meshes are the vanilla parcels as they are (`Parcel4_Text`, `Parcel2_Text`, `Parcel_Present_1`); our design (`art/make_box_texture.ps1`) is baked onto their UVs by `art/make_boxes.py` (Blender), which also renders the icons.
- Not in any loot table: spawn them through the admin item list.
