package os2

import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

Glob_Any :: struct {}
Glob_Star :: struct {}
Glob_Path_Separator :: struct {}
Glob_Class :: struct {
	negated: bool,
	runes: []rune,
	ranges: [][2]rune,
}

Glob_Element :: union {
	string,
	Glob_Any,
	Glob_Star,
	Glob_Path_Separator,
	^Glob_Class, // These are represented by pointers to keep the union size down.
}

/*
Parse a string pattern for matching paths.

The pattern interpretation follows the POSIX standard (§ 2.14.3 Patterns Used for Filename Expansion).

Here is a summary of the pattern syntax:

- `?` matches a single rune.
- `*` matches anything up to a system path separator, including nothing.
- `/` indicates a system path separator (even if it is something other than `/`).
- `[...]` forms a class set, which will match one rune from the set.
   Note that the class set cannot contain `/`.
   Ranges may be specified as such: `A-Z`.
- `[!...]` forms a negated class set which matches one rune _not_ in the set.
- All other intervening strings are matched verbatim.

NOTE: Exceptions are made on Windows systems:

- Plain strings are matched in a case-insensitive way.
- Starting a pattern with `/` will accept any volume (`"A:", "B:", "C:", ...`) if one is not specified.
- To match a specific volume, start the pattern with its letter and colon like so: `"c:/WINDOWS"`.
- UNC paths are not currently supported.

See the documentation for the directory `Walker` in this package if you need
greater control.
*/
@(require_results)
compile_path_pattern :: proc(pattern: string, allocator: runtime.Allocator) -> (compiled_pattern: []Glob_Element, err: Error) {
	compile_class :: proc(pattern: string, allocator: runtime.Allocator) -> (class: ^Glob_Class, err: Error) {
		class = new(Glob_Class, allocator) or_return
		last_rune: rune
		ranged := false

		runes := make([dynamic]rune, allocator) or_return
		ranges := make([dynamic][2]rune, allocator) or_return

		pattern := pattern
		if pattern[0] == '!' {
			class.negated = true
			pattern = pattern[1:]
		}

		for r in pattern {
			if ranged {
				append(&ranges, [2]rune{last_rune, r})
				ranged = false
				last_rune = {}
			} else {
				if r == '-' && last_rune != {} {
					ranged = true
				} else {
					if last_rune != {} {
						append(&runes, last_rune)
					}
					last_rune = r
				}
			}
		}

		if last_rune != {} {
			append(&runes, last_rune)
		}

		if ranged {
			// [abc-]
			append(&runes, '-')
		}

		shrink(&runes)
		shrink(&ranges)
		class.runes = runes[:]
		class.ranges = ranges[:]
		return
	}

	elements := make([dynamic]Glob_Element, allocator) or_return

	last_rune: rune // Used for collapsing asterisks.
	scan: for i := 0; i < len(pattern); /**/ {
		r, _ := utf8.decode_rune(pattern[i:])
		defer last_rune = r
		switch (r) {
		case '/':
			append(&elements, Glob_Path_Separator{})
			i += 1
		case '?':
			append(&elements, Glob_Any{})
			i += 1
		case '*':
			if last_rune != '*' {
				append(&elements, Glob_Star{})
			}
			i += 1
		case '[':
			if i == len(pattern) - 1 {
				append(&elements, "[")
				return
			}
			class_loop: for j := i + 1; j < len(pattern); j += 1 {
				if pattern[j] == '/' {
					// § 2.14.3.1
					// Classes may not contain path separators.
					break class_loop
				}
				if pattern[j] == ']' {
					append(&elements, compile_class(pattern[i+1:j], allocator) or_return)
					i = j + 1
					continue scan
				}
			}
			append(&elements, "[")
			i += 1
		case '\\':
			i += 1
			if i < len(pattern) {
				_, escaped_width := utf8.decode_rune(pattern[i:])
				append(&elements, pattern[i:i+escaped_width])
				i += escaped_width
			} else {
				append(&elements, "\\")
			}
		case:
			for j := i + 1; j < len(pattern); j += 1 {
				switch (pattern[j]) {
				case '?', '*', '[', '\\', '/':
					append(&elements, pattern[i:j])
					i = j
					continue scan
				}
			}
			append(&elements, pattern[i:])
			break scan
		}
	}

	shrink(&elements)
	return elements[:], nil
}

/*
Free memory allocated by `compile_path_pattern`.
*/
destroy_path_pattern :: proc(compiled_pattern: []Glob_Element, allocator: runtime.Allocator) {
	for elem in compiled_pattern {
		#partial switch element in elem {
		case ^Glob_Class:
			free(element, allocator)
		}
	}
	delete(compiled_pattern, allocator)
}

/*
Match a pattern compiled by `compile_path_pattern` against a path.
*/
@(require_results)
match_path :: proc(compiled_pattern: []Glob_Element, name: string, initial := true) -> (matched: bool) {
	match_class :: proc(class: ^Glob_Class, ru: rune) -> bool {
		for r in class.runes {
			if ru == r {
				return !class.negated
			}
		}
		for r in class.ranges {
			if r[0] <= ru && ru <= r[1] {
				return !class.negated
			}
		}
		return class.negated
	}

	name := name
	compiled_pattern := compiled_pattern

	if initial {
		compiled_pattern, name = _match_path_handle_start(compiled_pattern, name) or_return
	}

	match_loop: for elem, i in compiled_pattern {
		switch &element in elem {
		case string:
			// Check with `_are_paths_identical` to support case-insensitive comparison where it matters.
			if len(name) >= len(element) && _are_paths_identical(name[:len(element)], element) {
				name = name[len(element):]
			} else {
				return false
			}
		case Glob_Path_Separator:
			// Important to use `_is_path_separator` throughout in the event
			// the system supports multiple separator characters.
			if len(name) > 0 && _is_path_separator(name[0]) {
				name = name[1:]
			} else {
				return false
			}
		case Glob_Any:
			if len(name) > 0 && name[0] != '.' {
				// § 2.14.3.2
				// A leading period must be matched explicitly.
				_, width := utf8.decode_rune(name)
				name = name[width:]
			} else {
				return false
			}
		case ^Glob_Class:
			name_rune, width := utf8.decode_rune(name)
			if len(name) > 0 && match_class(element, name_rune) {
				name = name[width:]
			} else {
				return false
			}
		case Glob_Star:
			if len(name) == 0 {
				if i == len(compiled_pattern) - 1 {
					// This is a terminal asterisk with nothing left to match.
					return true
				} else {
					// There are other elements, and we've run out of text to match.
					return false
				}
			}
			if name[0] == '.' {
				// A leading period must be matched explicitly.
				return false
			}
			if i == len(compiled_pattern) - 1 {
				// This is a terminal asterisk, which means we match anything
				// so long as we don't encounter a path separator.
				for r in name {
					if r < utf8.RUNE_SELF && _is_path_separator(u8(r)) {
						return false
					}
				}
				return true
			}
			for r, j in name {
				if r < utf8.RUNE_SELF && _is_path_separator(u8(r)) {
					// § 2.14.3.1
					// An asterisk cannot cross path separators.
					name = name[j:]
					continue match_loop
				}
				if match_path(compiled_pattern[i+1:], name[j:], false) {
					return true
				}
			}
			return false
		}
	}

	return len(name) == 0
}

/*
Return a list of all paths on the system matching a pattern.

The pattern interpretation follows the POSIX standard (§ 2.14.3 Patterns Used for Filename Expansion).

See the documentation of `compile_path_pattern` for an overview.

NOTE: On Windows, trying to glob a pattern beginning with `/` will search the
volume of the current working directory.
*/
@(require_results)
glob :: proc(pattern: string, allocator: runtime.Allocator) -> (matches: []string, err: Error) {
	split_chunk :: proc(elements: []Glob_Element) -> (left, right: []Glob_Element) {
		for elem, i in elements {
			#partial switch _ in elem {
			case Glob_Path_Separator:
				return elements[:i], elements[1+i:]
			}
		}
		return elements, nil
	}

	find_chunk :: proc(dir: string, elements: []Glob_Element, results: ^[dynamic]string, allocator: runtime.Allocator, initial := false) -> Error {
		left, right := split_chunk(elements)

		dir_file, err := open(dir)
		if err == .Permission_Denied {
			return nil
		} else if err != nil {
			return err
		}
		defer close(dir_file)

		it := read_directory_iterator_create(dir_file)
		defer read_directory_iterator_destroy(&it)

		if len(right) == 0 {
			// All matches are results.
			for info in read_directory_iterator(&it) {
				if match_path(left, info.name, initial) {
					append(results, strings.clone(info.fullpath, allocator))
				}
			}
		} else {
			// We still have traversing to do.
			for info in read_directory_iterator(&it) {
				if match_path(left, info.name, initial) && info.type == .Directory {
					find_chunk(info.fullpath, right, results, allocator) or_return
				}
			}
		}
		return nil
	}

	dynamic_matches := make([dynamic]string, allocator) or_return

	TEMP_ALLOCATOR_GUARD()

	compiled_pattern := compile_path_pattern(pattern, temp_allocator()) or_return
	starting_dir, revised_pattern := _glob_get_starting_dir(compiled_pattern) or_return
	if len(revised_pattern) == 0 {
		// Special case for matching only the root.
		root, open_err := open(starting_dir)
		if open_err == nil {
			info := fstat(root, temp_allocator()) or_return
			append(&dynamic_matches, strings.clone(info.fullpath, allocator))
			close(root)
		} else if open_err == .Permission_Denied {
			// No access.
		} else if err != nil {
			err = open_err
		}
	} else {
		find_chunk(starting_dir, revised_pattern, &dynamic_matches, allocator, true) or_return
	}

	shrink(&dynamic_matches)
	return dynamic_matches[:], nil
}
