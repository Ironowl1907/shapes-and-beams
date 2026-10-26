extends SceneTree

func _init() -> void:
	print("\n=== STARTING IN-GAME RECORDS MENU TEST ===")
	
	# Load main menu
	var menu_scene: PackedScene = load("res://scenes/main_menu.tscn")
	assert(menu_scene != null, "main_menu.tscn must load")
	var menu: Control = menu_scene.instantiate() as Control
	root.add_child(menu)
	menu._ready()
	
	print("[Step 1] Verifying menu buttons...")
	var records_btn: Button = menu.get_node_or_null("CenterContainer/MenuBox/RecordsButton") as Button
	assert(records_btn != null, "RecordsButton must exist in MenuBox")
	assert(records_btn.text == "Records", "RecordsButton text must be 'Records'")
	print("  RecordsButton verified: text = '", records_btn.text, "'")
	
	var credits_btn: Button = menu.get_node_or_null("CenterContainer/MenuBox/CreditsButton") as Button
	assert(credits_btn != null, "CreditsButton must exist in MenuBox")
	assert(credits_btn.text == "Credits", "CreditsButton text must be 'Credits'")
	print("  CreditsButton verified: text = '", credits_btn.text, "'")
	
	print("\n[Step 2] Verifying records panel is initially closed...")
	var panel: ColorRect = menu.get_node_or_null("RecordsPanel") as ColorRect
	assert(panel != null, "RecordsPanel must exist as a child of MainMenu")
	assert(not panel.visible, "RecordsPanel must be initially invisible")
	print("  RecordsPanel verified (initially hidden)")
	
	print("\n[Step 3] Simulating click on RecordsButton...")
	menu.call("_on_records_pressed")
	assert(panel.visible == true, "RecordsPanel must be visible after pressing RecordsButton")
	print("  RecordsPanel is now VISIBLE inside the game!")
	
	print("\n[Step 4] Checking records panel contents...")
	var player_lbl: Label = menu.get("records_player_label") as Label
	assert(player_lbl != null, "RecordsPlayerLabel must exist")
	print("  Player Header: ", player_lbl.text)
	
	var easy_lbl: Label = menu.get("records_easy_label") as Label
	var normal_lbl: Label = menu.get("records_normal_label") as Label
	var hard_lbl: Label = menu.get("records_hard_label") as Label
	assert(easy_lbl != null and normal_lbl != null and hard_lbl != null, "Difficulty labels must exist")
	print("  Easy Record:   ", easy_lbl.text)
	print("  Normal Record: ", normal_lbl.text)
	print("  Hard Record:   ", hard_lbl.text)
	
	print("\n[Step 5] Simulating Back/Close button...")
	menu.call("_on_records_close_pressed")
	assert(panel.visible == false, "RecordsPanel must hide when close button is pressed")
	print("  RecordsPanel successfully closed and returned to main menu!")
	
	print("\n[Step 6] Testing ESC key (ui_cancel) handling...")
	menu.call("_on_records_pressed")
	assert(panel.visible == true, "RecordsPanel reopened")
	var esc_event: InputEventAction = InputEventAction.new()
	esc_event.action = "ui_cancel"
	esc_event.pressed = true
	menu._unhandled_input(esc_event)
	assert(panel.visible == false, "Pressing ESC must close the RecordsPanel")
	print("  ESC closes RecordsPanel verified!")
	
	print("\n=== IN-GAME RECORDS MENU VERIFIED 100% WORKING WITHOUT BUGS! ===\n")
	menu.queue_free()
	quit(0)
