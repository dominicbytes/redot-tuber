@tool
extends AcceptDialog

const OAUTH_GUIDE_URL: String = "https://developers.google.com/identity/protocols/oauth2/native-app"
const API_GUIDE_URL: String = "https://developers.google.com/youtube/v3/live/getting-started"


func _init() -> void:
	title = "Redot Tuber Setup"
	ok_button_text = "Close"
	min_size = Vector2i(620, 360)

	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	add_child(content)

	var heading: Label = Label.new()
	heading.text = "Connect a developer-owned YouTube API application"
	heading.add_theme_font_size_override("font_size", 20)
	content.add_child(heading)

	var explanation: Label = Label.new()
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.text = (
		"Each game developer or publisher supplies their own Google OAuth client ID and API key at runtime. " +
		"Redot Tuber never stores credentials in project.godot, scenes, resources, or editor settings."
	)
	content.add_child(explanation)

	_add_step(content, "1. Enable YouTube Data API v3 in your Google Cloud project.")
	_add_step(content, "2. Create a Desktop OAuth client and configure its consent screen.")
	_add_step(content, "3. Pass the client ID and the minimum named capabilities to YouTubeLiveClient at runtime.")
	_add_step(content, "4. Use docs/capability-matrix.md to review scopes, confirmations, quota, and account limits.")
	_add_step(content, "5. Keep quota, privacy, verification, and user-support ownership with your shipped game.")

	var links: HBoxContainer = HBoxContainer.new()
	content.add_child(links)
	var oauth_link: LinkButton = LinkButton.new()
	oauth_link.text = "OAuth installed-app guide"
	oauth_link.pressed.connect(func() -> void: OS.shell_open(OAUTH_GUIDE_URL))
	links.add_child(oauth_link)
	var api_link: LinkButton = LinkButton.new()
	api_link.text = "YouTube Live API guide"
	api_link.pressed.connect(func() -> void: OS.shell_open(API_GUIDE_URL))
	links.add_child(api_link)


func show_setup() -> void:
	popup_centered()


func _add_step(parent: VBoxContainer, text: String) -> void:
	var label: Label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	parent.add_child(label)
