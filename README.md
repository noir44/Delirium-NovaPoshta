# Delirium Nova Poshta Van

Project Zomboid Build 42 mod: Nova Poshta delivery vans.

- Vehicle scripts: `Base.StepVan_NovaPoshta` and `Base.Van_NovaPoshta` — copies of the vanilla `StepVan` and `Van` with their own skin.
- Textures: `media/textures/Vehicles/vehicle_stepvanshell_novaposhta.png`, `vehicle_vanshell_novaposhta.png` (1024×1024, vanilla UV layout), built by `art/make_livery.ps1`.
- The body is transparent in the texture, so the game paints it a random color (models `Vehicle_StepVan` / `Vehicles_Van`); the logo is opaque and stays red.
- Not added to any vehicle spawn zone: spawn it through the admin vehicle menu.
