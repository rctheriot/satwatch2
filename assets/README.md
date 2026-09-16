# Earth textures

Committed to the repo (NASA Visible Earth, public domain) so a clone runs with
no setup. `earth.gdshader` and `clouds.gdshader` are still defensive about a
missing file -- the globe falls back to flat shading, and the cloud shell just
hides itself -- so the demo still runs if one of these is ever deleted.

| File | Source | Resolution |
|---|---|---|
| `earth_day.jpg`    | Blue Marble Next Generation | 5400x2700 |
| `earth_night.jpg`  | Black Marble / Earth at Night | 2400x1200 |
| `earth_clouds.jpg` | Blue Marble cloud composite (record 57747) | 2048x1024 |
| `earth_ocean.jpg`  | Blue Marble specular / water mask | not available |

Equirectangular, longitude -180..180 left to right. Godot's `SphereMesh` UV
origin is a convention that has to be checked, not assumed -- `geo_uv()` in
`earth.gdshader` derives it instead of trusting the mesh's own UVs; see that
shader's comments before touching the mapping.

`earth_ocean.jpg` is unavailable at the NASA Visible Earth paths that serve
the other three (all return 404). `earth.gdshader` declares it
`hint_default_black`, so without it the globe is simply matte everywhere and
nothing breaks -- only the ocean specular highlight is missing.
