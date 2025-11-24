package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"sync"
)

// Config struct to read OutPath
type Config struct {
	OutPath string `json:"outPath"`
}

var sanRegexStr = `[\/:*?"><|]`

func sanitise(filename string) string {
	san := regexp.MustCompile(sanRegexStr).ReplaceAllString(filename, "_")
	return strings.TrimSuffix(san, "\t")
}

func readConfig() string {
	data, err := os.ReadFile("config.json")
	if err != nil {
		return "Nugs downloads"
	}
	var obj Config
	err = json.Unmarshal(data, &obj)
	if err != nil || obj.OutPath == "" {
		return "Nugs downloads"
	}
	return obj.OutPath
}

func main() {
	// 1. Determine OutPath
	outPath := readConfig()

	// 2. Check if scripts exist
	if _, err := os.Stat("./nugs_dl_fixed"); os.IsNotExist(err) {
		fmt.Println("Error: ./nugs_dl_fixed not found.")
		os.Exit(1)
	}
	if _, err := os.Stat("./update_album_tags.sh"); os.IsNotExist(err) {
		fmt.Println("Error: ./update_album_tags.sh not found.")
		os.Exit(1)
	}

	// 3. Prepare command
	cmd := exec.Command("./nugs_dl_fixed", os.Args[1:]...)
	
	// Create pipes for stdout and stderr
	stdoutPipe, err := cmd.StdoutPipe()
	if err != nil {
		fmt.Println("Error creating stdout pipe:", err)
		os.Exit(1)
	}
	stderrPipe, err := cmd.StderrPipe()
	if err != nil {
		fmt.Println("Error creating stderr pipe:", err)
		os.Exit(1)
	}

	if err := cmd.Start(); err != nil {
		fmt.Println("Error starting nugs_dl_fixed:", err)
		os.Exit(1)
	}

	// 4. Monitor output
	var foldersToTag []string
	var foldersMutex sync.Mutex

	// Multi-reader to print to stdout AND scan
	// We combine stdout and stderr for scanning? 
	// Typically logging goes to stdout in main.go. Stderr is for panic/errors.
	// The lines we care about ("Item...", "HLS-only...") are fmt.Println (stdout).
	
	// We want to stream stdout to the user's terminal AND parse it.
	pr, pw := io.Pipe()
	mw := io.MultiWriter(os.Stdout, pw)

	// Goroutine to copy cmd stdout to MultiWriter
	go func() {
		defer pw.Close()
		io.Copy(mw, stdoutPipe)
	}()

	// Goroutine to copy stderr to os.Stderr (pass-through)
	go func() {
		io.Copy(os.Stderr, stderrPipe)
	}()

	// Parse in main routine (reading from pipe)
	scanner := bufio.NewScanner(pr)
	
	itemRegex := regexp.MustCompile(`^Item \d+ of \d+:$`)
	hlsRegex := regexp.MustCompile(`HLS-only track\. Only AAC is available, tags currently unsupported\.`)
	
	// State
	var currentFolder string
	expectFolder := false
	
	// Using a map to avoid duplicates
	folderSet := make(map[string]bool)

	for scanner.Scan() {
		line := scanner.Text()
		trimmed := strings.TrimSpace(line)

		if itemRegex.MatchString(trimmed) {
			expectFolder = true
			currentFolder = ""
			continue
		}

		if expectFolder {
			if trimmed == "" {
				continue // Skip empty lines? main.go might output blank lines
			}
			if strings.HasPrefix(trimmed, "Invalid URL") || 
			   strings.HasPrefix(trimmed, "Video-only album") ||
			   strings.HasPrefix(trimmed, "Failed to get") {
				expectFolder = false // Failed to get folder name or invalid
				continue
			}
			
			// This line is likely the folder name
			currentFolder = line // Keep original whitespace for now, though main.go usually prints clean strings
			
			// Handle chopping logic from main.go
			// if len(albumFolder) > 120 { albumFolder = albumFolder[:120] }
			if len(currentFolder) > 120 {
				currentFolder = currentFolder[:120]
			}
			
			expectFolder = false
			continue
		}

		if currentFolder != "" && hlsRegex.MatchString(trimmed) {
			sanitisedName := sanitise(currentFolder)
			foldersMutex.Lock()
			if !folderSet[sanitisedName] {
				folderSet[sanitisedName] = true
				foldersToTag = append(foldersToTag, sanitisedName)
			}
			foldersMutex.Unlock()
		}
	}

	if err := cmd.Wait(); err != nil {
		// Don't exit yet, we might still need to tag what was downloaded successfully
		fmt.Println("\nnugs_dl_fixed finished with error:", err)
	}

	// 5. Run tagger on collected folders
	if len(foldersToTag) > 0 {
		fmt.Println("\n--- Running auto-tagger on HLS-only downloads ---")
		for _, folder := range foldersToTag {
			fmt.Printf("Tagging: %s\n", folder)
			
			tagCmd := exec.Command("./update_album_tags.sh", "-f", outPath, "-n", folder)
			tagCmd.Stdout = os.Stdout
			tagCmd.Stderr = os.Stderr
			
			if err := tagCmd.Run(); err != nil {
				fmt.Printf("Error running tagger on '%s': %v\n", folder, err)
			}
		}
		fmt.Println("--- Auto-tagging complete ---")
	}
}

