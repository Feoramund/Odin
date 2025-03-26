package tests_core_os_os2

import os "core:os/os2"
import    "core:log"
import    "core:slice"
@require import    "core:strings"
import    "core:testing"
@require import    "core:unicode/utf8"

@test
test_match_path :: proc(t: ^testing.T) {
	Test_Case :: struct {
		pattern: string,
		path: string,
		should_match: bool,
	}

	test_cases := [?]Test_Case{
		{`a`,               `a`,                 true  },
		{`a`,               `b`,                 false },
		{`?`,               `f`,                 true  },
		{`?`,               `foo`,               false },
		{`/`,               `/`,                 true  },
		{`\`,               `\`,                 true  },
		{`\`,               ``,                  false },
		{`*`,               ``,                  true  },
		{`*`,               `foo`,               true  },
		{`/*`,              `/foo`,              true  },
		{`/*`,              `/foo/`,             false },
		{`/home/\`,         `/home/\`,           true  },
		{`/home/\\`,        `/home/\`,           true  },
		{`\[o]`,            `[o]`,               true  },
		{`\*z`,             `*z`,                true  },
		{`\?z`,             `?z`,                true  },
		{`[-z]`,            `z`,                 true  },
		{`[-z]`,            `-`,                 true  },
		{`[-z]`,            `a`,                 false },
		{`[a-]`,            `a`,                 true  },
		{`[a-]`,            `-`,                 true  },
		{`[a-]`,            `z`,                 false },
		{`[---]`,           `-`,                 true  },
		{`[,--]`,           `-`,                 true  },
		{`[+--]`,           `+`,                 true  },
		{`[+--]`,           `,`,                 true  },
		{`[a-z]`,           `a`,                 true  },
		{`[a-z]`,           `x`,                 true  },
		{`[a-z]`,           `-`,                 false },
		{`[!a]`,            `a`,                 false },
		{`[!a]`,            `b`,                 true  },
		{`[!a-z]`,          `1`,                 true  },
		{`[!a-z]`,          `a`,                 false },
		{`/home/[oo`,       `/home/[oo`,         true  },
		{`/home/[oo`,       `/home/[ee`,         false },
		{`/home/a[b/c]d`,   `/home/a[b/c]d`,     true  },
		{`/home/*.txt`,     `/home/foo.txt`,     true  },
		{`/home/*/bar.txt`, `/home/foo/bar.txt`, true  },
		{`/home/[f]oo.txt`, `/home/foo.txt`,     true  },
		{`/usr/bin/*[s-t]`, `/usr/bin/ls`,       true  },
		{`/usr/bin/*[ab]`,  `/usr/bin/cd`,       false },
		{`/usr/share/???`,  `/usr/share/かごめ`, true  },
		{`.foo`,            `.foo`,              true  },
		{`*foo`,            `.foo`,              false },
		{`.*`,              `.foo`,              true  },
		{`?`,               `.`,                 false },
		{`.*/bar`,          `.foo/bar`,          true  },
		{`/*/*/bar`,        `/home/foo/bar`,     true  },
		{`/*/*/*`,          `/home/foo/bar`,     true  },
		{`a*b*c`,           `abc`,               true  },
		{`a*b*c`,           `abbac`,             true  },
		{`a*b*c`,           `aabbac`,            true  },
		{`a*b*c`,           `aavac`,             false },
		{`a*?`,             `aaaabc`,            true  },
		{`a*?`,             `ac`,                true  },
		{`a*?z`,            `acz`,               true  },
		{`a*?z`,            `abcz`,              true  },
		{`a*?`,             `a`,                 false },
		{`a**`,             `a`,                 true  },
		{`a**`,             `ab`,                true  },
		{`a?*`,             `a`,                 false },
		{`a?*`,             `ab`,                true  },
		{`a?*`,             `abc`,               true  },
	}

	when ODIN_OS == .Windows {
		for &tc in test_cases {
			tc.path = posix_to_dos_path(tc.path)
			tc.path = strings.to_upper(tc.path, context.temp_allocator)
		}
	}

	for tc in test_cases {
		pattern, err := os.compile_path_pattern(tc.pattern, context.temp_allocator)
		log.debugf("%v = %v", tc.pattern, pattern)
		result := os.match_path(pattern, tc.path)
		testing.expectf(t, result == tc.should_match && err == nil, "expected match_path(%q, %q) -> %v; got %v, %v", tc.pattern, tc.path, tc.should_match, result, err)
	}
}

@test
test_glob :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		candidates := [?]string{
			`C:\Documents and Settings`,
			`C:\Program Files`,
			`C:\Program Files (x86)`,
			`C:\RECYCLER`,
			`C:\System Volume Information`,
			`C:\WINDOWS`,
			`C:\Users`,
			`C:\AUTOEXEC.BAT`,
			`C:\boot.ini`,
		}
	} else {
		candidates := [?]string{
			`/bin`,
			`/boot`,
			`/dev`,
			`/etc`,
			`/home`,
			`/root`,
			`/sbin`,
			`/tmp`,
			`/usr`,
			`/var`,
		}
	}

	pattern := "/*"

	results, err := os.glob(pattern, context.temp_allocator)
	log.debugf(`glob(%q) results: %v`, pattern, results)
	testing.expect(t, err == nil)
	found := 0
	for entry in results {
		if slice.contains(candidates[:], entry) {
			found += 1
		}
	}
	testing.expectf(t, found >= 3, `expected glob(%q) to find at least 3 valid candidates for this system.
	valid candidates: %v
	got: %v`, pattern, candidates, results)
}

@test
test_glob_root_special_case :: proc(t: ^testing.T) {
	{
		pattern := "/"
		results, err := os.glob(pattern, context.temp_allocator)
		testing.expectf(t, len(results) == 1 && err == nil, "expected glob(%q) to return one result, got: %v, %v", pattern, results, err)
	}
	{
		pattern := "/*"
		when ODIN_OS == .Windows {
			// Get "C:\"
			cwd, cwd_err := os.get_working_directory(context.temp_allocator)
			testing.expect(t, cwd_err == nil)
			for r, i in cwd {
				if r <= utf8.RUNE_SELF && os.is_path_separator(u8(r)) {
					cwd = cwd[:i+1]
					break
				}
			}
			root := cwd
		} else {
			root := "/"
		}
		results, err := os.glob(pattern, context.temp_allocator)
		pass := true
		for entry in results {
			if entry == "/" {
			}
		}
		testing.expectf(t, pass && err == nil, "expected glob(%q) to not contain the root %q, got: %v, %v", pattern, root, results, err)
	}
}
