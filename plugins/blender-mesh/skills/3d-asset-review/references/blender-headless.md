# Blender headless notes (verified on Blender 5.2, Windows)

Things that silently cost time in practice. Each was hit at least once.

## Running
- `blender -b FILE.blend --python script.py -- args…` — script args come after `--`.
  Use `--factory-startup` when building a scene from scratch (no user prefs/add-ons).
- Grep the console for your own log prefix; Blender prints a lot (`Fra:` lines, a harmless
  `HIPEW initialization failed` on NVIDIA machines).
- `grep` into a file buffers until the process ends — logs look empty while it runs.

## Paths and I/O
- Give **absolute** paths to `scene.render.filepath`, `image.filepath_raw` and saves.
  Relative paths can be written somewhere unexpected or fail silently.
- Reading/writing raw label or data images: set `image.colorspace_settings.name = "Non-Color"`
  first, otherwise values are colour-converted. `image.pixels` rows are bottom-up.
- Windows console is cp949 in Korean locales: printing `—` or other non-ASCII can crash a
  script after its files were written. Use `sys.stdout.reconfigure(encoding="utf-8")`.
  `python -I` ignores `PYTHONIOENCODING`.
- The system Python may not have numpy; Blender's bundled Python does. Do array work in
  Blender, keep system-Python helpers to Pillow-only code.
- User names with non-ASCII characters can be mangled when a temp path is passed between
  processes — prefer project-relative work folders.

## Blender 5.x API changes
- `Material.use_nodes` / `World.use_nodes` are deprecated (node trees always exist).
- Compositor: `scene.compositing_node_group = bpy.data.node_groups.new(..., "CompositorNodeTree")`,
  add an output socket via `tree.interface.new_socket(...)`, end in `NodeGroupOutput`
  (there is no `CompositorNodeComposite`). Glare options are input sockets
  (`inputs["Type"].default_value = "Bloom"`).
- EEVEE/Cycles engine names and Principled inputs: `"Emission Color"`, `"Coat Weight"`,
  `"Sheen Weight"`, `"Transmission Weight"`, `"Specular IOR Level"`.

## Look-dev
- AgX view transform pushes bright emission towards white. For glowing parts use a pure
  emitter (black base colour, specular 0), moderate strength (2–5) and a Bloom glare.
- Coplanar faces z-fight (a ground plane at the same height as a stage top rendered black).
- Per-vertex baked AO needs enough samples (~256) and a few neighbour-averaging passes, or
  it shows as speckles.

## Geometry recipes
- Metaball visible radius ≈ 0.574 × element radius (threshold 0.6, stiffness 2).
- Voxel remesh output can contain coincident duplicate vertices → Quadriflow cancels with a
  "manifold" warning even though the mesh is manifold → `bmesh.ops.remove_doubles(dist=1e-4)`.
- Quadriflow with symmetry is only approximately symmetric (~1–3 cm on a 2 m character).
- Painting by region in code: a region test must also check distance from the region's
  surface, or everything along its extension gets painted (stripes on a forehead came from
  a tail-leaf test).
- Keep fitting proxies and built geometry identical (a sphere-chain proxy vs flat-capped
  tube build left feet floating 5.5 cm).
