# Earth textures

Not committed -- these are large NASA downloads. The globe falls back to flat
shading without them, so the rest of the demo still runs.

Fetch from NASA Visible Earth (public domain) and place here:

| File | Source |
|---|---|
| `earth_day.jpg`   | Blue Marble Next Generation, 8k |
| `earth_night.jpg` | Black Marble / Earth at Night, 8k |
| `earth_ocean.jpg` | Blue Marble specular / water mask, 8k |

Equirectangular, longitude -180..180 left to right. Godot's `SphereMesh` UV
origin is a convention that has to be checked, not assumed -- after adding these,
run the ground-track registration check in the README before trusting any
sub-satellite position.

`earth_ocean.png` is currently unavailable at the NASA Visible Earth paths above
(all return 404). `earth.gdshader` declares it `hint_default_black`, so without
it the globe is simply matte everywhere and nothing breaks — only the ocean
specular highlight is missing.
