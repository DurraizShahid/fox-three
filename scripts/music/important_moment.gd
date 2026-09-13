extends Resource
class_name ImportantMoment
## A short high-importance marker inside a song (e.g. exact drop hit).
## Separate from MusicSection so overlapping hype spikes can be authored
## without splitting sections.

@export_range(0.0, 3600.0, 0.05) var time: float = 0.0 ## center time in seconds
@export_range(0.05, 20.0, 0.05) var duration: float = 2.0 ## window in seconds
@export_range(0.0, 1.0, 0.01) var intensity: float = 1.0 ## how hard this hits
@export var label: String = "DROP" ## debug / HUD label, e.g. DROP, HIT, FILL
@export var triggers_drop_surge: bool = false ## if true, MusicReactiveDirector fires the big speed/FOV punch

func start_time() -> float:
	return maxf(0.0, time - duration * 0.5)

func end_time() -> float:
	return time + duration * 0.5

func contains(t: float) -> bool:
	return t >= start_time() and t < end_time()

func progress_at(t: float) -> float:
	var d: float = duration
	if d <= 0.01:
		return 0.0
	return clampf((t - start_time()) / d, 0.0, 1.0)
