.PHONY: help start healthy-check fault-on verify fault-off reset stop record-ready

LABCTL = scenario/control/labctl

help:
	@printf '%s\n' \
		'start          Start the lab scenario.' \
		'healthy-check   Check the healthy scenario.' \
		'fault-on        Enable the planned fault.' \
		'verify          Verify the planned scenario.' \
		'fault-off       Disable the planned fault.' \
		'reset          Reset the planned scenario.' \
		'stop           Stop the lab scenario.' \
		'record-ready    Prepare the planned recording state.'

start healthy-check fault-on verify fault-off reset stop record-ready:
	@$(LABCTL) $@
