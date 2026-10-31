# Delirium Express

Project Zomboid Build 42 mod: Delirium Express, the server's own delivery service (vans, boxes, waybills, wall signs, terminal app). Internal ids (`DelNovaPoshta`, `DelNP`, `*_NovaPoshta`) are left from its first name and stay so that saves and server configs keep working.

Logo: `art/delirium_express_logo.png`; the box mark cut out of it — `art/delirium_express_box.png`.

- Vehicle scripts: `Base.StepVan_NovaPoshta` and `Base.Van_NovaPoshta` — copies of the vanilla `StepVan` and `Van` with their own skin.
- Textures: `media/textures/Vehicles/vehicle_stepvanshell_novaposhta_{white,black}.png`, `vehicle_vanshell_novaposhta_{white,black}.png` (1024×1024, vanilla UV layout), built by `art/make_livery.ps1`.
- Two skins each, white and black (models `Vehicle_StepVan_NoRandom` / `Vehicles_Van_NoRandom`, fully opaque texture); the skin is picked at random on spawn, admins switch it with *Next skin*. The body detail hidden under the vanilla paint mask is kept as shading (`make_livery.ps1 -paint`).
- Not added to any vehicle spawn zone: spawn it through the admin vehicle menu.

## Boxes

- Items `DelNP.Box5`, `DelNP.Box10`, `DelNP.Box25`: cardboard containers with capacity 5, 10 and 25.
- Meshes are the vanilla parcels as they are (`Parcel4_Text`, `Parcel2_Text`, `Parcel_Present_1`); our design (`art/make_box_texture.ps1`) is baked onto their UVs by `art/make_boxes.py` (Blender), which also renders the icons.
- Not in any loot table: spawn them through the admin item list.

## Sealing parcels

- Context menu of a box in your inventory: **Seal parcel...** opens a waybill form. You type the recipient's branch No. (digits) and the recipient's **login**; the number (sequential, `0000001`...), the sender (your login) and the date (game date) are filled in by the server.
- A sealed box shows its number in its name, cannot be looked into, and nothing can be put in or taken out. **View waybill** shows the filled-in form to anyone.
- **Open parcel** is offered only to the recipient (login, case-insensitive) and to admins; the box must be in their inventory. After that it is an ordinary box again and can be sealed anew (new number). The waybill keeps a red "Opened: who, date" mark.
- Register: `Zomboid/Lua/DelNovaPoshta/waybills.txt` on the server, one tab-separated line per seal and per opening; numbers never repeat even if the world rolls back. Server Lua can list it with `DelNP.waybills()`.
- The lock is client-side (container button hidden, transfers refused), like vanilla's own container checks: a modified client could get round it.

## Delirium Terminal app

With the Delirium Terminal mod enabled, computers get a **[8] DELIRIUM EXPRESS** menu entry: pickup requests, parcel status by waybill number and "my parcels", branches and staff (admin creates branches and names directors, directors add staff), the staff desk (list of all parcels with filters all / in work / my branches, statuses ACCEPTED / IN TRANSIT / ARRIVED) and the price list (admin edits). Identity is the game login. Data: `Zomboid/Lua/DelNovaPoshta/` (`org.txt`, `requests.txt`, `waybills.txt`, `prices.txt`).

## Payments (with Delirium Shops)

Staff set the delivery price when they mark a parcel ACCEPTED (0 = free); the sender pays it from their Delirium Shops bank account in the terminal. The money goes to the cash desk of the accepting branch; the branch director (or an admin) pays out from it. Until paid, a parcel cannot go IN TRANSIT and cannot be opened by the recipient. Notifications (accepted / to pay / arrived) go to the terminal mail of every terminal account the player registered, and over their head when online.
