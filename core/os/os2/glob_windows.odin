#+private
package os2

import "core:strings"

_match_path_handle_start :: proc(compiled_pattern: []Glob_Element, name: string) -> (revised_pattern: []Glob_Element, revised_name: string, ok: bool) {
	revised_pattern = compiled_pattern
	revised_name = name

	#partial switch element in compiled_pattern[0] {
	case Glob_Path_Separator:
		// Match any volume when we have an initial separator.
		vol_len := _volume_name_len(name)
		if vol_len > 0 {
			revised_pattern = compiled_pattern[1:]
			revised_name = name[vol_len:]
			if len(revised_name) > 0 && _is_path_separator(revised_name[0]) {
				revised_name = revised_name[1:]
			}
			ok = true
		}
	case string:
		vol_len := _volume_name_len(element)
		if vol_len > 0 {
			// Match a specific volume.
			if _volume_name_len(name) == vol_len && strings.equal_fold(element, name[:vol_len]) {
				revised_pattern = compiled_pattern[1:]
				revised_name = name[vol_len:]
				if len(revised_name) > 0 && _is_path_separator(revised_name[0]) {
					revised_name = revised_name[1:]
				}
				ok = true
			}
		} else {
			ok = true
		}
	}

	return
}

_glob_get_starting_dir :: proc(compiled_pattern: []Glob_Element) -> (starting_dir: string, revised_pattern: []Glob_Element, err: Error) {
	starting_dir = "."
	revised_pattern = compiled_pattern

	switch element in compiled_pattern[0] {
	case Glob_Path_Separator:
		// If the pattern begins with a path separator, we're targeting the
		// volume of the current working directory.
		cwd := _get_working_directory(temp_allocator()) or_return
		starting_dir = cwd[:_volume_name_len(cwd)+1]
		revised_pattern = compiled_pattern[1:]
	case Glob_Any, Glob_Star, ^Glob_Class:
		// Targetting the current directory.
		break
	case string:
		// We must check if the initial string represents a volume.
		vol_len := _volume_name_len(element)
		if vol_len > 0 {
			starting_dir = strings.concatenate({element[:vol_len], `\`}, temp_allocator()) or_return
			revised_pattern = compiled_pattern[1:]
		}
	}
	return
}
