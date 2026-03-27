# AGENTS.md - Airgap-Bundler

This file provides guidelines for agentic coding agents operating in this repository.

## Project Overview

Airgap-Bundler is a helper script for loading and distributing Juno Innovations setup to non-internet enabled machines. It packages Docker images and Git repositories into a tar.gz archive for airgap deployment.

## Build Commands

### Build the Bundle
```bash
# Using make (recommended)
make build

# Or run directly
./build-bundle.sh
```

This script:
1. Pulls Docker images and saves them as tar files
2. Clones Git repositories as bare repositories
3. Creates a docker-compose.yaml and load.sh script
4. Packages everything into `airgap-bundle.tar.gz`

### Prerequisites
- Docker must be installed and running
- Git must be available
- Network access to pull the defined Docker images and clone repositories

### Configuration
Edit the arrays at the top of `build-bundle.sh` to modify:
- `GIT_REPOS`: Array of Git repository URLs to include
- `DOCKER_IMAGES`: Array of Docker image names to pull and bundle

## Linting

### Shell Script Linting
This is a shell script project. Use [shellcheck](https://www.shellcheck.net/) for static analysis via devbox:

```bash
# Using make
make lint

# Or directly with devbox
devbox run -- shellcheck build-bundle.sh test-integration.sh

# Run shellcheck with specific rules
devbox run -- shellcheck -e SC1090,SC1091 build-bundle.sh
```

### Running a Single Script Check
```bash
devbox run -- shellcheck build-bundle.sh
```

## Testing

### Running a Single Test

Run the integration test script:

```bash
# Using make
make test

# Or directly
./test-integration.sh
```

The integration test performs:
1. Builds the bundle
2. Extracts to a temporary directory
3. Starts services via load.sh
4. Tests Docker registry (push/pull an image)
5. Tests Git server (clones a repository)
6. Cleans up all artifacts regardless of pass/fail

### Manual Testing

For manual testing:
1. Run the build script and verify the output tar.gz is created
2. Extract and run the load.sh script on a target machine
3. Verify Docker services start correctly (Git server on port 8080, Registry on port 5000)

## Code Style Guidelines

### Shell Script Conventions

#### Error Handling
- Always use `set -e` at the top of scripts to exit on errors
- Use `set -u` to exit on undefined variables
- Use `set -o pipefail` for pipeline error handling
- Check exit codes explicitly for critical operations

Example:
```bash
#!/bin/bash
set -euo pipefail
```

#### Variable Naming
- Use UPPERCASE for constants/environment variables
- Use lowercase for local variables
- Use descriptive names: `BUNDLE_NAME`, `WORK_DIR`, `TIMESTAMP`
- Prefix private variables with underscore when needed: `_internal_var`

#### Functions
- Use `function_name()` or `function function_name()` syntax consistently
- Declare local variables with `local` keyword
- Use descriptive function names: `pull_image()`, `clone_repository()`

Example:
```bash
function pull_image() {
    local image="$1"
    docker pull "${image}"
}
```

#### Quoting
- Always quote variable expansions: `"${VAR}"` not `$VAR`
- Use double quotes for string expansion, single quotes for literal strings
- Quote command substitutions: `$(command)` not `\`command\``

#### Input Validation
- Validate required arguments at function start
- Use meaningful error messages
- Exit with non-zero status on validation failure

#### File Paths
- Use absolute paths when possible, or resolve relative paths with `cd`
- Use `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` for script directory
- Quote file paths containing spaces

#### Arrays
- Declare arrays with `local -a` for local scope
- Use proper array syntax: `${array[@]}` for all elements
- Iterate over arrays with proper quoting

Example:
```bash
local -a ARRAY=("item1" "item2")
for item in "${ARRAY[@]}"; do
    echo "${item}"
done
```

#### Here Documents
- Use `<< 'EOF'` for literal content (no variable expansion)
- Use `<< "EOF"` or `<<EOF` when variable expansion is needed
- Indent heredoc content for readability when appropriate

#### Permissions
- Ensure scripts are executable: `chmod +x script.sh`
- Set appropriate file permissions in scripts when creating files

#### Comments
- Use comments to explain non-obvious logic
- Comment sections with: `# === Section Name ===`
- Keep comments concise and meaningful

#### Command Style
- Prefer `local` variables over global
- Use `[[ ]]` over `[ ]` for tests (bash-specific)
- Use `$(command)` over backticks for command substitution
- Use long-form options when they improve readability: `--help` over `-h`

### Example Pattern from This Project

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
BUNDLE_NAME="airgap-bundle"
WORK_DIR="${SCRIPT_DIR}/${BUNDLE_NAME}-${TIMESTAMP}"

GIT_REPOS=(
    "https://github.com/example/repo1.git"
    "https://github.com/example/repo2.git"
)

function clone_repositories() {
    for repo in "${GIT_REPOS[@]}"; do
        local repo_name
        repo_name=$(basename "${repo}" .git)
        git clone --depth 100 --bare "${repo}" "${WORK_DIR}/git-repos/${repo_name}.git"
    done
}
```

## Directory Structure

```
Airgap-Bundler/
├── AGENTS.md           # This file
├── Makefile            # Build, lint, test, and clean targets
├── build-bundle.sh     # Main build script
├── test-integration.sh # Integration test script
├── update_dns.sh      # DNS update helper script
├── devbox.json         # Devbox configuration
├── .gitignore          # Git ignore rules
├── README.md           # Project readme
└── .idea/              # IDE configuration
```

## Common Tasks

### Adding a New Git Repository
Add the repository URL to the `GIT_REPOS` array in `build-bundle.sh`.

### Adding a New Docker Image
Add the image name to the `DOCKER_IMAGES` array in `build-bundle.sh`.

### Modifying the docker-compose.yaml
The docker-compose template is embedded in `build-bundle.sh`. Edit the here document starting with `cat > "${WORK_DIR}/docker-compose.yaml" << 'EOF'`.

### Updating DNS in ArgoCD Application
When moving the installation to a new environment, update the DNS hostname in the ArgoCD "genesis" Application using the helper script:

```bash
# From the bundle directory
./update_dns.sh my.new.host
```

The script will:
1. Detect if k3s is available and use `k3s kubectl` accordingly
2. Verify cluster connectivity (with debug steps if unreachable)
3. Verify Application 'genesis' exists in argocd namespace
4. Update the following values:
   - `repoURL` hostname in sources
   - `env.NEXTAUTH_URL` helm parameter
   - `host:` value in helm values
5. Verify all values were updated correctly

Example:
```bash
./update_dns.sh new.juno-deployment.com
```

Debug if cluster unreachable:
```bash
kubectl config current-context    # Check current context
kubectl get nodes                 # Verify cluster connectivity
kubectl get pods -n argocd        # Verify ArgoCD is installed
```

### Adding a New Helper Script
To add a new script to the bundle:
1. Create the script in the project root directory
2. Ensure it has proper permissions (executable, proper shebang)
3. Add the copy step in `build-bundle.sh` (after step 5 where load.sh is created)
