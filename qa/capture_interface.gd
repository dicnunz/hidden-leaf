extends SceneTree
var out := ""
func _initialize() -> void:
 root.always_on_top = true
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--qa-out="): out=arg.trim_prefix("--qa-out=")
 call_deferred("capture")
func capture() -> void:
 if out.is_empty() or DisplayServer.get_name()=="headless": quit(2); return
 DirAccess.make_dir_recursive_absolute(out)
 var world = load("res://main.tscn").instantiate()
 root.add_child(world)
 for i in range(100): await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(out+"/hidden-menu.png")
 var settings: Button
 for button in world.hud.find_children("*","Button",true,false):
  if button.text=="Settings": settings=button
 assert(settings!=null)
 settings.pressed.emit()
 for i in range(5): await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(out+"/hidden-settings.png")
 for button in world.hud.find_children("*","Button",true,false):
  if button.is_visible_in_tree(): assert(root.get_visible_rect().encloses(button.get_global_rect()))
 world.hud.set_paused(false)
 for i in range(10): await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(out+"/hidden-walking.png")
 print("INTERFACE_CAPTURE_PASS")
 quit()
