# Vouch
A terminal-based game compatibility checker combining ProtonDB and AreWeAntiCheat via fzf.

## About
`vouch` is a lightweight Bash utility designed to streamline checking game compatibility on Linux. Instead of manually searching multiple databases, this script aggregates data from **ProtonDB** and **AreWeAntiCheatYet** into a single searchable `fzf` interface.

### Key Features
* **Fuzzy Search:** Quickly find titles without exact string matching.
* **Unified View:** See performance ratings and anti-cheat status simultaneously.
* **Zero Bloat:** Minimalist script using standard tools (`curl`, `python3`, `fzf`).

## Usage / Quick Start
```bash
# Give the script execution permissions
chmod +x vouch.sh

# Run the utility
./vouch.sh
```

Dependencies
fzf: For the interactive search interface.

curl: To fetch live data from API endpoints.

python3: For parsing JSON responses.
