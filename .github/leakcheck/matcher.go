// Package leakscan checks text against the never-leak patterns for public
// repos (public IPs and prefixes, the tailnet domain, tracker names,
// internal hostnames, GSM names and so on). The patterns are secret
// themselves, so they come from a file mounted from GSM, never from a repo.
// A finding names the rule and where it was found, never what matched:
// what the agent sees ends up in logs and PR text.
//
// The file is one pattern per line, "name<TAB>regexp"; blank lines and
// lines starting with # are skipped. Patterns are Go regexps.
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
)

type rule struct {
	name string
	re   *regexp.Regexp
}

// Scanner holds the compiled patterns. The zero value finds nothing.
type Scanner struct{ rules []rule }

// Parse compiles a pattern file's contents.
func Parse(data []byte) (*Scanner, error) {
	s := &Scanner{}
	sc := bufio.NewScanner(bytes.NewReader(data))
	n := 0
	for sc.Scan() {
		n++
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		name, expr, ok := strings.Cut(line, "\t")
		if !ok || !regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$`).MatchString(name) || strings.TrimSpace(expr) == "" {
			return nil, fmt.Errorf("leakscan: line %d: want name<TAB>regexp", n)
		}
		re, err := regexp.Compile(strings.TrimSpace(expr))
		if err != nil {
			// The error text would echo the pattern; name the rule only.
			return nil, fmt.Errorf("leakscan: line %d (%s): bad regexp", n, strings.TrimSpace(name))
		}
		s.rules = append(s.rules, rule{name: strings.TrimSpace(name), re: re})
	}
	if sc.Err() != nil {
		return nil, fmt.Errorf("leakscan: pattern file unreadable")
	}
	return s, nil
}

// Load reads a pattern file. A missing path means no patterns.
func Load(path string) (*Scanner, error) {
	if path == "" {
		return &Scanner{}, nil
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("leakscan: pattern file unreadable")
	}
	return Parse(data)
}

// Len is the number of patterns.
func (s *Scanner) Len() int {
	if s == nil {
		return 0
	}
	return len(s.rules)
}

// Finding is one match: the rule's name, where, and the line number (1
// based; 0 when the source has no lines, like a PR title).
type Finding struct {
	Rule  string
	Where string
	Line  int
}

func (f Finding) String() string {
	if f.Line > 0 {
		return fmt.Sprintf("rule %s in %s line %d", f.Rule, f.Where, f.Line)
	}
	return fmt.Sprintf("rule %s in %s", f.Rule, f.Where)
}

// Scan checks text from where (a file, "PR title", "commit <sha> message").
func (s *Scanner) Scan(where, text string) []Finding {
	if s.Len() == 0 || text == "" {
		return nil
	}
	var out []Finding
	lines := strings.Split(text, "\n")
	for i, l := range lines {
		for _, r := range s.rules {
			if r.re.MatchString(l) {
				line := i + 1
				if len(lines) == 1 {
					line = 0
				}
				out = append(out, Finding{Rule: r.name, Where: s.safeLocation(where), Line: line})
			}
		}
	}
	return out
}

// ScanPaths checks NUL-delimited raw Git paths, including empty files and
// names whose patch headers Git quotes. Findings never include the path.
func (s *Scanner) ScanPaths(paths []byte) []Finding {
	if s.Len() == 0 {
		return nil
	}
	var out []Finding
	for _, path := range bytes.Split(paths, []byte{0}) {
		if len(path) == 0 {
			continue
		}
		for _, r := range s.rules {
			if r.re.Match(path) {
				out = append(out, Finding{Rule: r.name, Where: "diff path"})
			}
		}
	}
	return out
}

// ScanDiff checks the added lines of a unified diff, naming files and their
// new line numbers.
func (s *Scanner) ScanDiff(diff string) []Finding {
	if s.Len() == 0 {
		return nil
	}
	var out []Finding
	file, line := "", 0
	hunk := regexp.MustCompile(`^@@ -\d+(?:,\d+)? \+(\d+)`)
	for _, l := range strings.Split(diff, "\n") {
		switch {
		case strings.HasPrefix(l, "diff --git "):
			// Empty added files have no +++ header or hunk.
			out = append(out, s.Scan("diff path", l)...)
		case strings.HasPrefix(l, "+++ "):
			path := strings.TrimPrefix(l, "+++ ")
			if strings.HasPrefix(path, "\"") {
				decoded, err := strconv.Unquote(path)
				if err != nil {
					// Do not use malformed or escaped paths in diagnostics.
					out = append(out, Finding{Rule: "scan-error", Where: "diff path"})
					file = "redacted-location"
					continue
				}
				path = decoded
			} else {
				path = strings.TrimSuffix(path, "\t")
			}
			file = strings.TrimPrefix(path, "b/")
			out = append(out, s.Scan("diff path", file)...)
		case strings.HasPrefix(l, "@@"):
			if m := hunk.FindStringSubmatch(l); m != nil {
				fmt.Sscanf(m[1], "%d", &line)
			}
		case strings.HasPrefix(l, "+"):
			for _, r := range s.rules {
				if r.re.MatchString(l[1:]) {
					out = append(out, Finding{Rule: r.name, Where: s.safeLocation(file), Line: line})
				}
			}
			line++
		case strings.HasPrefix(l, "-"):
		default:
			line++
		}
	}
	return out
}

// Locations are untrusted too: a filename may itself contain a forbidden value.
func (s *Scanner) safeLocation(where string) string {
	// Check both forms: rendering controls or invalid UTF-8 can create a match
	// that was absent from the original filename.
	rendered := strings.Map(func(r rune) rune {
		if r < 32 || r == 127 {
			return '_'
		}
		return r
	}, where)
	for _, r := range s.rules {
		if r.re.MatchString(where) || r.re.MatchString(rendered) {
			return "redacted-location"
		}
	}
	return rendered
}
