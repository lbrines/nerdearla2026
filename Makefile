.PHONY: help start healthy-check fault-on verify fault-off reset stop record-ready

LABCTL = scenario/control/labctl

help:
	@printf '%s\n' \
		'start          Iniciar el escenario del lab.' \
		'healthy-check   Comprobar el escenario saludable.' \
		'fault-on        Habilitar la falla planificada.' \
		'verify          Verificar el escenario planificado.' \
		'fault-off       Deshabilitar la falla planificada.' \
		'reset          Restablecer el escenario planificado.' \
		'stop           Detener el escenario del lab.' \
		'record-ready    Preparar el estado planificado para la grabación.'

start healthy-check fault-on verify fault-off reset stop record-ready:
	@$(LABCTL) $@
