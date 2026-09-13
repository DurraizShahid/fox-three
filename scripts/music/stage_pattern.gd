class_name StagePattern
## Shared enumeration of procedural stage pattern families.
## StageDirector and StageTheme both reference this so adding a new
## pattern is a single enum entry + handler in StageDirector.

enum Type {
	OPEN_FLIGHT,       ## sparse, long sightlines
	RING_STREAM,       ## straight line of rings
	RING_WAVE,         ## sine-wave ring heights
	RING_SLALOM,       ## alternating lane rings
	VERTICAL_WAVE,     ## strong up/down lane undulation
	PILLAR_SLALOM,     ## alternating side pillars
	LOW_ALTITUDE_RUN,  ## hugging ground
	HIGH_ALTITUDE_RUN, ## high lane bias
	LANE_WEAVE,        ## frequency-modulated lane positions
	TIGHT_CORRIDOR,    ## narrow corridor, close posts
	WIDE_CORRIDOR,     ## wide open
	DROP_RUSH,         ## fast straight rush (drop hit)
	SOLO_FLOW,         ## flowing lines for dramatic banking
	CRESCENDO_CLIMB,   ## gradually rising intensity/density
	BREAKDOWN_OPEN,    ## open breathing room
	CHAOS,             ## dense random
	CUSTOM,            ## fully overridden by level script
}

## Display names for debug HUD.
static func display_name(p: int) -> String:
	match p:
		Type.OPEN_FLIGHT: return "OPEN_FLIGHT"
		Type.RING_STREAM: return "RING_STREAM"
		Type.RING_WAVE: return "RING_WAVE"
		Type.RING_SLALOM: return "RING_SLALOM"
		Type.VERTICAL_WAVE: return "VERTICAL_WAVE"
		Type.PILLAR_SLALOM: return "PILLAR_SLALOM"
		Type.LOW_ALTITUDE_RUN: return "LOW_ALTITUDE_RUN"
		Type.HIGH_ALTITUDE_RUN: return "HIGH_ALTITUDE_RUN"
		Type.LANE_WEAVE: return "LANE_WEAVE"
		Type.TIGHT_CORRIDOR: return "TIGHT_CORRIDOR"
		Type.WIDE_CORRIDOR: return "WIDE_CORRIDOR"
		Type.DROP_RUSH: return "DROP_RUSH"
		Type.SOLO_FLOW: return "SOLO_FLOW"
		Type.CRESCENDO_CLIMB: return "CRESCENDO_CLIMB"
		Type.BREAKDOWN_OPEN: return "BREAKDOWN_OPEN"
		Type.CHAOS: return "CHAOS"
		Type.CUSTOM: return "CUSTOM"
		_: return "UNKNOWN"

## All values for iterating.
static func all_types() -> Array[int]:
	return [
		Type.OPEN_FLIGHT, Type.RING_STREAM, Type.RING_WAVE, Type.RING_SLALOM,
		Type.VERTICAL_WAVE, Type.PILLAR_SLALOM, Type.LOW_ALTITUDE_RUN,
		Type.HIGH_ALTITUDE_RUN, Type.LANE_WEAVE, Type.TIGHT_CORRIDOR,
		Type.WIDE_CORRIDOR, Type.DROP_RUSH, Type.SOLO_FLOW,
		Type.CRESCENDO_CLIMB, Type.BREAKDOWN_OPEN, Type.CHAOS, Type.CUSTOM,
	]
