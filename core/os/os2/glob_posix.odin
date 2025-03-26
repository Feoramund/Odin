#+private
#+build linux, darwin, netbsd, freebsd, openbsd, wasi
package os2

_match_path_handle_start :: proc(compiled_pattern: []Glob_Element, name: string) -> (revised_pattern: []Glob_Element, revised_name: string, ok: bool) {
	// No special handling for POSIX paths.
	return compiled_pattern, name, true
}

_glob_get_starting_dir :: proc(compiled_pattern: []Glob_Element) -> (starting_dir: string, revised_pattern: []Glob_Element, err: Error) {
	switch element in compiled_pattern[0] {
	case Glob_Path_Separator:
		// If the pattern begins with a path separator, we're targeting the
		// root of the filesystem.
		starting_dir = "/"
		revised_pattern = compiled_pattern[1:]
	case Glob_Any, Glob_Star, string, ^Glob_Class:
		// Targetting the current directory.
		starting_dir = "."
		revised_pattern = compiled_pattern
	}
	return
}
