// This file is merely to see if Odin can successfully run a barebones program
// without the C runtime, to ensure the entry points are working.
package no_crt

import "base:runtime"

main :: proc() {
	runtime.println_any("Hellope!")
}
