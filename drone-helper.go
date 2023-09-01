package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"
	"text/template"

	"github.com/containrrr/shoutrrr"
)

const colorSuccess = "0x4BB543"
const colorFailure = "0xFC100D"
const colorUnknown = "0x808080"

// template assuming basic markdown support
// (plainer and richer options available, depending on service)
var mdTmpl = template.Must(template.New("markdown-message").Parse(
	`**Build [#{{.BuildNumber}}]({{.BuildLink}})**
**of [{{.Repo}}]({{.RepoLink}}):{{.Branch}}@[{{slice .CommitAfter 0 7}}]({{.CommitLink}})**
**by {{.Author}}**
**{{.Status}}**
`))

type Build struct {
	BuildNumber  string
	BuildEvent   string
	BuildLink    string
	Repo         string
	RepoLink     string
	Branch       string
	CommitBefore string
	CommitAfter  string
	CommitLink   string
	Author       string
	Status       string
}

func getenvStrict(key string) string {
	res := os.Getenv(key)
	if res == "" {
		log.Fatalf("%s: required variable not defined", key)
	}
	return res
}

func getBuildInfo() Build {

	return Build{
		BuildNumber:  getenvStrict("DRONE_BUILD_NUMBER"),
		BuildEvent:   getenvStrict("DRONE_BUILD_EVENT"),
		BuildLink:    getenvStrict("DRONE_BUILD_LINK"),
		Repo:         getenvStrict("DRONE_REPO"),
		RepoLink:     getenvStrict("DRONE_REPO_LINK"),
		Branch:       getenvStrict("DRONE_SOURCE_BRANCH"),
		CommitBefore: getenvStrict("DRONE_COMMIT_BEFORE"),
		CommitAfter:  getenvStrict("DRONE_COMMIT_AFTER"),
		CommitLink:   getenvStrict("DRONE_COMMIT_LINK"),
		Author:       getenvStrict("DRONE_COMMIT_AUTHOR"),
		Status:       strings.ToUpper(getenvStrict("DRONE_BUILD_STATUS")),
	}

}

func cacheBaseName(bld Build, depsHash string) string {
	return fmt.Sprintf("cache--%s:%s", bld.Repo, depsHash)
}

func cacheAlias(bld Build) string {
	return fmt.Sprintf("cache--%s:%s", bld.Repo, bld.CommitAfter)
}

// cacheRebuildNeeded determines whether the current build requires cache to be [re]built.
// If a rebuild is not necessary, the docker image id of the cache is returned. Otherwise, return nil.
func cacheRebuildNeeded(bld Build, depsHash string) *string {

	// rebuild if triggered by cron
	if bld.BuildEvent == "cron" {
		fmt.Println("Cache rebuild forced by cron job.")
		return nil
	}

	// rebuild if promoted (web interface: top right "..." -> "Promote")
	if bld.BuildEvent == "promote" {
		fmt.Println("Cache rebuild forced by promoted job.")
		return nil
	}

	// build if no cache exists
	// cache is uniquely identified by the hash of the dependency files, written as the image tag
	findCache := exec.Command("docker", "image", "ls", "--quiet", "--filter", fmt.Sprintf("reference=*/*:%s", depsHash))
	cacheIds_, err := findCache.Output()
	checkErrorFatal(err)
	cacheIds := strings.Fields(string(cacheIds_))

	if len(cacheIds) <= 0 {
		fmt.Println("No suitable cache found.")
		return nil
	}

	res := string(cacheIds[0])
	fmt.Printf("Cache found.\n\tDocker image ID: %s\n\tDependency SHA256: %s\n", res, depsHash)
	return &res

}

func checkErrorFatal(err error) {
	if err != nil {
		log.Fatalln(err)
	}
}

func deduplicate[T comparable](l []T) []T {
	set := make(map[T]struct{})
	res := []T{}
	for _, e := range l {
		if _, in := set[e]; !in {
			set[e] = struct{}{}
			res = append(res, e)
		}
	}
	return res
}

// hashDeps takes a list of filenames, and produces a single unique hash of all the files' contents.
func hashDeps(deps []string) string {

	sum := make([]byte, sha256.Size)

	for _, dep := range deduplicate(deps) {

		data, err := os.ReadFile(dep)
		checkErrorFatal(err)

		fileSum := sha256.Sum256(data)

		// note: using XOR, so result is independent of order
		for i := range sum {
			sum[i] ^= fileSum[i]
		}

	}

	return hex.EncodeToString(sum)
}

// verbose redirects a Cmd's output to stdout/err, and prints the command itself.
func verbose(cmd *exec.Cmd) {
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	fmt.Println(cmd.String())
}

// rebuildCache rebuilds cache if necessary, and tags it with a new alias,
// under which drone will expect it.
func rebuildCache(deps []string) {

	bld := getBuildInfo()
	depsHash := hashDeps(deps)
	cacheId := cacheRebuildNeeded(bld, depsHash)

	// [re]build the cache image if necessary
	if cacheId == nil {

		newCacheName := cacheBaseName(bld, depsHash)

		fmt.Println("[Re]building cache...")
		buildCmd := exec.Command("docker", "build", "--no-cache", "-t", newCacheName, ".")
		verbose(buildCmd)
		err := buildCmd.Run()
		checkErrorFatal(err)

		cacheIds_, err := exec.Command("docker", "image", "ls", "--quiet", newCacheName).Output()
		checkErrorFatal(err)
		cacheIds := strings.Fields(string(cacheIds_))

		if len(cacheIds) <= 0 {
			log.Fatalf("Could not find docker image that was just [supposedly] built: %s", newCacheName)
		}

		cacheId = &cacheIds[0]

	}

	fmt.Println("Creating an alias for drone to refer to the cached image by...")
	// create an alias for the cache image
	aliasCmd := exec.Command("docker", "image", "tag", *cacheId, cacheAlias(bld))
	verbose(aliasCmd)
	err := aliasCmd.Run()
	checkErrorFatal(err)

}

func notifyDiscord() {

	bld := getBuildInfo()

	discordID := getenvStrict("DISCORD_WEBHOOK_ID")
	discordToken := getenvStrict("DISCORD_WEBHOOK_TOKEN")

	var color string

	switch bld.Status {
	case "SUCCESS":
		color = colorSuccess
	case "FAILURE":
		color = colorFailure
	default:
		color = colorUnknown
	}

	var buf bytes.Buffer
	mdTmpl.Execute(&buf, bld)
	message := buf.String()

	discordURL := fmt.Sprintf("discord://%s@%s?color=%s&splitLines=false", discordToken, discordID, color)

	fmt.Printf("Sending message to Discord:\n%s\n", message)
	err := shoutrrr.Send(discordURL, message)
	checkErrorFatal(err)
	fmt.Println("Message sent.")

}

func main() {

	cacheFlags := flag.NewFlagSet("cache", flag.ExitOnError)
	cacheDepsArg := cacheFlags.String("deps", "", "List of files on which cache depends (space-separated)")

	notifyFlags := flag.NewFlagSet("notify", flag.ExitOnError)
	notifyDiscordArg := notifyFlags.Bool("discord", true, `Send notification to Discord.
Assumes DISCORD_WEBHOOK_ID and DISCORD_WEBHOOK_TOKEN in environment.`)

	if len(os.Args) < 2 {
		log.Fatalln("expected 'cache' or 'notify' subcommands")
	}

	switch os.Args[1] {

	case "cache":
		cacheFlags.Parse(os.Args[2:])
		cacheDeps := strings.Fields(*cacheDepsArg)
		if len(cacheDeps) <= 0 {
			log.Fatalln("cannot indentify cache: no dependencies given (--deps)")
		}
		rebuildCache(cacheDeps)
	case "notify":
		notifyFlags.Parse(os.Args[2:])
		switch {
		case *notifyDiscordArg:
			notifyDiscord()
		}
	default:
		log.Fatalln(fmt.Sprintf("unexpected subcommand: %s", os.Args[1]))
	}
}
