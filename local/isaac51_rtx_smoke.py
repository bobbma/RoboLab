"""Check standalone RTX initialization and render a local scene without assets."""

from isaacsim import SimulationApp

app = SimulationApp({"headless": True, "multi_gpu": False, "active_gpu": 0, "physics_gpu": 0})
try:
    import omni.replicator.core as rep
    import omni.usd

    omni.usd.get_context().new_stage()
    rep.create.sphere(position=(0, 0, 0))
    rep.create.light(light_type="Dome", intensity=1000)
    camera = rep.create.camera(position=(3, 3, 3), look_at=(0, 0, 0))
    product = rep.create.render_product(camera, (256, 256))
    rgb = rep.AnnotatorRegistry.get_annotator("rgb")
    rgb.attach(product)
    rep.orchestrator.step(rt_subframes=4)
    pixels = rgb.get_data()
    assert pixels.shape[:2] == (256, 256), f"Unexpected RGB shape: {pixels.shape}"
    assert pixels[..., :3].max() > 0, "RTX produced a black frame"
    print(f"RTX_SMOKE_PASSED shape={pixels.shape}", flush=True)
finally:
    app.close()
