package main

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"testing"
)

func TestTrustedEntrypoint(t *testing.T) {
	cmd := exec.Command("python3", "-B", "check_test.py")
	_, source, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("locate entrypoint fixtures")
	}
	cmd.Dir = filepath.Dir(source)
	if err := cmd.Run(); err != nil {
		t.Fatal("trusted entrypoint tests failed")
	}
}

func TestBackstop(t *testing.T) {
	// Synthetic words only. Assertions never print input or captured output.
	const forbidden = "synthetic-forbidden-marker"
	patterns := "fixture\t" + forbidden + "\n"
	repo := t.TempDir()
	git := func(args ...string) string {
		t.Helper()
		cmd := exec.Command("git", append([]string{"-C", repo}, args...)...)
		cmd.Env = append(os.Environ(), "GIT_AUTHOR_NAME=Test", "GIT_AUTHOR_EMAIL=test@example.invalid", "GIT_COMMITTER_NAME=Test", "GIT_COMMITTER_EMAIL=test@example.invalid")
		b, err := cmd.Output()
		if err != nil {
			t.Fatal("fixture git operation failed")
		}
		return strings.TrimSpace(string(b))
	}
	git("init", "-q")
	git("commit", "--allow-empty", "-qm", "base")
	base := git("rev-parse", "HEAD")
	write := func(name, data string) {
		t.Helper()
		if os.WriteFile(filepath.Join(repo, name), []byte(data), 0600) != nil {
			t.Fatal("fixture write failed")
		}
	}
	write("data.txt", forbidden+"\n")
	git("add", ".")
	git("commit", "-qm", "addition")
	added := git("rev-parse", "HEAD")
	write("data.txt", "safe\n")
	git("add", ".")
	git("commit", "-qm", "remove transient value")
	removed := git("rev-parse", "HEAD")
	git("commit", "--allow-empty", "-qm", forbidden)
	message := git("rev-parse", "HEAD")
	metadata := filepath.Join(t.TempDir(), "metadata.json")
	check := func(name, from, to, rules, data string, want int, location string) {
		t.Helper()
		t.Run(name, func(t *testing.T) {
			if os.WriteFile(metadata, []byte(data), 0600) != nil {
				t.Fatal("metadata write failed")
			}
			var out bytes.Buffer
			code := run([]string{repo, from, to, metadata}, rules, &out)
			if code != want {
				t.Fatal("unexpected scan outcome")
			}
			if strings.Contains(out.String(), forbidden) {
				t.Fatal("output echoed fixture")
			}
			if location != "" && !strings.Contains(out.String(), location) {
				t.Fatal("missing finding location")
			}
		})
	}
	check("introduced diff", base, added, patterns, `{}`, 1, "data.txt")
	check("transient historical diff", base, removed, patterns, `{}`, 1, "data.txt")
	check("commit message", removed, message, patterns, `{}`, 1, "message")
	check("clean", added, removed, patterns, `{}`, 0, "")
	check("PR title edit", added, removed, patterns, `{"title":"`+forbidden+`"}`, 1, "PR title")
	check("PR body edit", added, removed, patterns, `{"body":"`+forbidden+`"}`, 1, "PR body")
	check("missing secret", added, removed, "", `{}`, 2, "scan-error")
	check("empty secret", added, removed, "# only a comment", `{}`, 2, "scan-error")
	check("bad regex", added, removed, patterns+"bad\t"+forbidden+"[", `{}`, 2, "scan-error")
	check("unsafe rule ID", added, removed, forbidden+" [\tx", `{}`, 2, "scan-error")
	check("invalid metadata", added, removed, patterns, forbidden, 2, "scan-error")
	check("missing object", added, strings.Repeat("a", 40), patterns, `{}`, 2, "scan-error")
	check("empty range", added, added, patterns, `{}`, 2, "scan-error")
	write("binary.dat", "\x00"+forbidden)
	git("add", ".")
	git("commit", "-qm", "binary fixture")
	binary := git("rev-parse", "HEAD")
	check("binary-marked content", message, binary, patterns, `{}`, 1, "binary.dat")
	write(forbidden, "")
	git("add", ".")
	git("commit", "-qm", "empty path fixture")
	emptyPath := git("rev-parse", "HEAD")
	check("empty sensitive path", binary, emptyPath, patterns, `{}`, 1, "diff path")
	write(forbidden, forbidden)
	git("add", ".")
	git("commit", "-qm", "path fixture")
	check("sensitive path", message, git("rev-parse", "HEAD"), patterns, `{}`, 1, "redacted-location")
}

// Real Git objects exercise quoting, empty paths and diagnostic redaction.
func TestQuotedPaths(t *testing.T) {
	names := []string{"synthetic\"marker", `synthetic\marker`, "synthetic\tmarker", "synthetic\nmarker", "synthétic-marker", "synthetic\x01marker"}
	for i, name := range names {
		t.Run(strconv.Itoa(i), func(t *testing.T) {
			repo := t.TempDir()
			git := func(args ...string) string {
				t.Helper()
				cmd := exec.Command("git", append([]string{"-C", repo}, args...)...)
				cmd.Env = append(os.Environ(), "GIT_AUTHOR_NAME=Test", "GIT_AUTHOR_EMAIL=test@example.invalid", "GIT_COMMITTER_NAME=Test", "GIT_COMMITTER_EMAIL=test@example.invalid")
				data, err := cmd.Output()
				if err != nil {
					t.Fatal("fixture git operation failed")
				}
				return strings.TrimSpace(string(data))
			}
			git("init", "-q")
			git("commit", "--allow-empty", "-qm", "base")
			base := git("rev-parse", "HEAD")
			expr := strings.ReplaceAll(regexp.QuoteMeta(name), "\n", `\n`)
			rules := "fixture\t" + expr + "|synthetic-payload\n"
			for _, content := range []string{"", "synthetic-payload\n"} {
				if os.WriteFile(filepath.Join(repo, name), []byte(content), 0600) != nil {
					t.Fatal("fixture write failed")
				}
				git("add", ".")
				git("commit", "-qm", "path fixture")
				head := git("rev-parse", "HEAD")
				metadata := filepath.Join(t.TempDir(), "pr.json")
				if os.WriteFile(metadata, []byte(`{}`), 0600) != nil {
					t.Fatal("fixture metadata failed")
				}
				var out bytes.Buffer
				if run([]string{repo, base, head, metadata}, rules, &out) != 1 {
					t.Fatal("unexpected scan outcome")
				}
				result := out.String()
				if !strings.Contains(result, "rule fixture in diff path") {
					t.Fatal("path bypass")
				}
				if content != "" && !strings.Contains(result, "rule fixture in redacted-location line 1") {
					t.Fatal("location redaction failed")
				}
				for _, input := range []string{name, strconv.Quote(name), "synthetic-payload"} {
					if strings.Contains(result, input) {
						t.Fatal("diagnostic echoed fixture")
					}
				}
				base = head
			}
		})
	}
}

// Sanitization must not turn an otherwise harmless path into forbidden output.
func TestNoEchoAfterLocationRendering(t *testing.T) {
	for i, name := range []string{"synthetic\tmarker", "synthetic\nmarker", "synthetic\rmarker", "synthetic\vmarker", "synthetic\bmarker", "synthetic\x01marker", "synthetic\x7fmarker", "synthetic\xffmarker"} {
		t.Run(strconv.Itoa(i), func(t *testing.T) {
			repo := t.TempDir()
			git := func(args ...string) string {
				t.Helper()
				cmd := exec.Command("git", append([]string{"-C", repo}, args...)...)
				cmd.Env = append(os.Environ(), "GIT_AUTHOR_NAME=Test", "GIT_AUTHOR_EMAIL=test@example.invalid", "GIT_COMMITTER_NAME=Test", "GIT_COMMITTER_EMAIL=test@example.invalid")
				data, err := cmd.Output()
				if err != nil {
					t.Fatal("fixture git operation failed")
				}
				return strings.TrimSpace(string(data))
			}
			git("init", "-q")
			git("commit", "--allow-empty", "-qm", "base")
			base := git("rev-parse", "HEAD")
			if os.WriteFile(filepath.Join(repo, name), []byte("payload-marker\n"), 0600) != nil {
				t.Fatal("fixture write failed")
			}
			git("add", ".")
			git("commit", "-qm", "content fixture")
			head := git("rev-parse", "HEAD")
			rules := "hidden\tsynthetic_marker|synthetic\ufffdmarker\npayloadfixture\tpayload-marker\n"
			metadata := filepath.Join(t.TempDir(), "pr.json")
			if os.WriteFile(metadata, []byte(`{}`), 0600) != nil {
				t.Fatal("fixture metadata failed")
			}
			var out bytes.Buffer
			if run([]string{repo, base, head, metadata}, rules, &out) != 1 {
				t.Fatal("unexpected scan outcome")
			}
			result := out.String()
			if !strings.Contains(result, "rule payloadfixture in redacted-location line 1") {
				t.Fatal("missing redacted content finding")
			}
			for _, forbidden := range []string{"synthetic_marker", "synthetic\ufffdmarker", "payload-marker", name} {
				if strings.Contains(result, forbidden) {
					t.Fatal("diagnostic echoed fixture")
				}
			}
		})
	}
}
