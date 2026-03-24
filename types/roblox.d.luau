declare task: {
	delay: (seconds: number, fn: (...any) -> (), ...any) -> thread,
	defer: (fn: (...any) -> (), ...any) -> thread,
	spawn: (fn: (...any) -> (), ...any) -> thread,
	wait: (seconds: number?) -> number
}