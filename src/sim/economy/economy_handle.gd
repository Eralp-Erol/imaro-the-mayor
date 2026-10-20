class_name EconomyHandle
extends RefCounted
## `EconomyBootstrap.create` sonucu: ekonomili facade + sistem + yapılandırma (T-014/T-017 entegrasyon noktası).

var facade: SimFacadeImpl
var system: EconomySystem
var config: EconomyConfig
