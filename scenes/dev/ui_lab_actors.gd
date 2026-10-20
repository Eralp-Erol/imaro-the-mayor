class_name UiLabActors
extends VBoxContainer
## ui_lab DEV paneli: "aktör/grup seçimi" giriş noktasının önizlemesi (T-021 ölçüt 2). Aktörler yalnız facade'dan
## okunur: anlık görüntüdeki gruplar ve meclis grupları, parsel sahipleri, olay akışındaki aktörler. Bir aktör
## seçilince `actor_chosen(ref)` -> sahip `ReasonPanel.show_subject(ref)` açar. Gerçek ekranlarda (T-020 sicil
## listesi, T-022 meclis) aynı çağrı satırlardan yapılır; bu panel oyuncu UI'ı değildir.

signal actor_chosen(actor_ref: StringName)

var _ctx: UiContext = null


static func create(ctx: UiContext, facade: SimFacade) -> UiLabActors:
	var a := UiLabActors.new()
	a._ctx = ctx
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if facade.is_mock():
		a.add_child(MockBadge.create())
	a.add_child(UiFactory.label(UiText.t(&"reason.open_actor"), UiTheme.V_LABEL_MUTED, true))
	var seen := {}
	for actor in UiLabActors.actors_of(facade):
		if seen.has(actor.ref()):
			continue
		seen[actor.ref()] = true
		var b := UiFactory.button(ctx, UiText.actor_name(actor), false)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(a.actor_chosen.emit.bind(actor.ref()))
		a.add_child(b)
	if seen.is_empty():
		a.add_child(UiFactory.label(UiText.t(&"state.empty.generic"), UiTheme.V_LABEL_MUTED, true))
	return a


static func actors_of(facade: SimFacade) -> Array[ActorRef]:
	var out: Array[ActorRef] = []
	var snap := facade.snapshot()
	for g in snap.group_reactions:
		out.append(g.group)
	for bloc in snap.council.blocs:
		out.append(bloc.bloc)
	for pv in facade.parcel_views(facade.parcel_ids()):
		out.append(pv.owner)
	for e in facade.events_since(0):
		if e.actor != null:
			out.append(e.actor)
	var valid: Array[ActorRef] = []
	for a in out:
		if a != null and a.is_valid():
			valid.append(a)
	return valid
