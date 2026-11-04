// This program reads repository objects as data. It never checks out PR code.
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"regexp"
	"strings"
)

func main() { os.Exit(run(os.Args[1:], os.Getenv("NEVER_LEAK_PATTERNS"), os.Stdout)) }

func run(args []string, patterns string, out io.Writer) int {
	fail := func() int { fmt.Fprintln(out, "rule scan-error in scanner line 0"); return 2 }
	if len(args) != 4 {
		return fail()
	}
	s, err := Parse([]byte(patterns))
	if err != nil || s.Len() == 0 {
		return fail()
	}
	sha := regexp.MustCompile(`^[0-9a-f]{40}$`)
	if !sha.MatchString(args[1]) || !sha.MatchString(args[2]) {
		return fail()
	}
	metadata, err := os.ReadFile(args[3])
	if err != nil {
		return fail()
	}
	var pr struct {
		Title string `json:"title"`
		Body  string `json:"body"`
	}
	if json.Unmarshal(metadata, &pr) != nil {
		return fail()
	}
	findings := append(s.Scan("PR title", pr.Title), s.Scan("PR body", pr.Body)...)
	git := func(a ...string) ([]byte, error) {
		cmd := exec.Command("git", append([]string{"--no-replace-objects", "-C", args[0], "-c", "core.hooksPath=/dev/null"}, a...)...)
		// No secret or API token is needed by the local object reader.
		cmd.Env = []string{"PATH=" + os.Getenv("PATH"), "HOME=/nonexistent", "GIT_CONFIG_NOSYSTEM=1", "GIT_TERMINAL_PROMPT=0", "GIT_NO_LAZY_FETCH=1", "LC_ALL=C"}
		return cmd.Output()
	}
	// Missing objects, shallow ancestry and empty ranges must never turn green.
	shallow, err := git("rev-parse", "--is-shallow-repository")
	if err != nil || strings.TrimSpace(string(shallow)) != "false" {
		return fail()
	}
	commits, err := git("rev-list", "--reverse", args[1]+".."+args[2])
	if err != nil || len(strings.Fields(string(commits))) == 0 {
		return fail()
	}
	for _, commit := range strings.Fields(string(commits)) {
		if !sha.MatchString(commit) {
			return fail()
		}
		message, err := git("show", "-s", "--format=%B", commit)
		if err != nil {
			return fail()
		}
		findings = append(findings, s.Scan("commit "+commit+" message", string(message))...)
		paths, err := git("diff-tree", "--root", "-m", "-r", "--name-only", "-z", "--no-renames", "--format=", commit)
		if err != nil {
			return fail()
		}
		findings = append(findings, s.ScanPaths(paths)...)
		// Compare merges to every parent; text mode covers binary-marked blobs.
		diff, err := git("diff-tree", "--root", "-m", "-r", "-p", "--text", "--no-ext-diff", "--no-textconv", "--no-renames", "--format=", commit)
		if err != nil {
			return fail()
		}
		findings = append(findings, s.ScanDiff(string(diff))...)
	}
	for _, f := range findings {
		fmt.Fprintln(out, f.String())
	}
	if len(findings) != 0 {
		return 1
	}
	return 0
}
