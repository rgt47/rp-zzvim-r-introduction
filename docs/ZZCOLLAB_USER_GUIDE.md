<!-- zzcollab ZZCOLLAB_USER_GUIDE.md v0.3.0 -->
# ZZCOLLAB User Guide

## Table of Contents

1. [What is ZZCOLLAB?](#what-is-zzcollab)
2. [Quick Start](#quick-start)
3. [Docker Profile System](#docker-profile-system)
4. [Project Structure](#project-structure)
5. [Development Workflow](#development-workflow)
6. [Package Management](#package-management)
7. [Team Collaboration](#team-collaboration)
8. [Build System with Make](#build-system-with-make)
9. [Configuration System](#configuration-system)
10. [GitHub Actions CI/CD](#github-actions-cicd)
11. [GitLab support](#gitlab-support)
12. [Troubleshooting](#troubleshooting)
13. [Platform-Specific Notes](#platform-specific-notes)

## What is ZZCOLLAB?

ZZCOLLAB is a framework for creating reproducible research compendia.
Each compendium is a self-contained project that combines code, data,
documentation, and a computational environment specification to enable
complete reproducibility.

### Key Features

- Docker-based reproducibility with isolated computational environments
- Two-layer architecture separating team infrastructure from
  individual package management
- Four Docker profiles ranging from ~650 MB to ~4.2 GB
- Pure-shell dependency validation (no host R required)
- Automatic renv snapshot on container exit
- Content-addressable Docker build caching
- GitHub Actions CI/CD for testing and validation

### Architecture Overview

ZZCOLLAB uses a two-layer reproducibility model:

**Layer 1 -- Docker Profile (team/shared).** The team lead selects a
Docker profile that defines the base image, system libraries, and
pre-installed R packages. This layer is fixed once chosen and shared
by all team members via Docker Hub.

**Layer 2 -- renv.lock (personal/collaborative).** Any team member can
add R packages inside the container using standard `install.packages()`
calls. The `.Rprofile` auto-snapshots `renv.lock` on exit, and the
lock file accumulates packages from all contributors.

The **five pillars** of a zzcollab workspace are: Dockerfile +
renv.lock + .Rprofile + source code + data.

## Quick Start

### Prerequisites

- **Docker** installed and running
- **Git** for version control
- **Make** for build automation
- **GitHub CLI** (`gh`) for repository management (optional)

### Solo Developer

```bash
mkdir my-analysis && cd my-analysis
zzc tidyverse                   # full setup with tidyverse
make docker-build && make r     # build image, start R
```

The `tidyverse` profile was formerly named `analysis`; `analysis` is retained
as a deprecated alias, so `zzc analysis` still works.

### Team Lead

```bash
zzc config set dockerhub-account mylab   # one-time config
mkdir study && cd study
zzc tidyverse                   # full setup
zzc dockerhub                   # push image to Docker Hub
zzc github                      # create GitHub repo and push
```

### Team Member

```bash
git clone https://github.com/mylab/study.git
cd study
make docker-build               # build from Dockerfile
make r                          # start development
```

### Daily Development

```bash
make r                          # enter container
# ... work in R ...
q()                             # exit (auto-snapshots renv.lock)
make docker-test                # run tests
git add . && git commit -m "Add analysis" && git push
```

## Docker Profile System

### Complete Profiles

Each profile is a predefined combination of base image, system
libraries, and R packages. Select one with `zzc <profile>`:

| Profile | Base Image | Size | Use Case |
|---------|-----------|------|----------|
| `minimal` | rocker/r-ver | ~650 MB | Essential development (CLI only) |
| `tidyverse` | rocker/tidyverse | ~1.2 GB | Data analysis with tidyverse |
| `rstudio` | rocker/rstudio | ~980 MB | RStudio Server development |
| `publishing` | rocker/verse | ~4.2 GB | Manuscript rendering (rmarkdown, bookdown, LaTeX) |

The `tidyverse` profile was formerly named `analysis`; `analysis` is retained
as a deprecated alias. The `publishing` profile is capability-adaptive: it
renders PDF by default when a LaTeX toolchain is present and falls back to HTML
otherwise. Its LaTeX package closure is pre-baked into the image at build time,
so PDF rendering needs no runtime install.

For other specialized environments, build from a base image instead of a
profile (see [Custom Composition](#custom-composition)):

| Environment | Base Image |
|-------------|-----------|
| Shiny web applications | rocker/shiny base image |
| Machine learning | tidyverse profile + ML packages via renv |

```bash
zzc tidyverse                   # new project with tidyverse
zzc publishing                  # manuscript rendering (PDF-adaptive)
zzc list profiles               # show all profiles with descriptions
```

If a workspace already exists, running `zzc <profile>` switches the
Docker profile by regenerating the Dockerfile.

### Custom Composition

Build from a specific base image when no built-in profile fits:

```bash
zzc docker --base-image rocker/r-ver
```

Additional R packages are added via renv inside the container (see
[Package Management](#package-management)). Each built-in profile
bundles a curated package set; the bundles below document those sets:

**R Package Bundles** (built into profiles):

| Bundle | Packages | Required Libs |
|--------|----------|---------------|
| `minimal` | renv, devtools, usethis, tinytest, roxygen2 | minimal |
| `tidyverse` | renv, devtools, tidyverse, here | minimal |

```bash
zzc list pkgs                   # show all package bundles
zzc list libs                   # show all system library bundles
zzc list                        # show everything
```

### Automatic System Dependency Detection

ZZCOLLAB scans your code for R package usage and maps packages to
their required system libraries:

```bash
make check-system-deps          # report missing system deps
```

This eliminates manual library specification for most workflows.

## Project Structure

Running `zzc tidyverse` in an empty directory creates the following:

```
myproject/
├── DESCRIPTION                 # R package metadata
├── NAMESPACE                   # Export list (roxygen2-generated)
├── LICENSE                     # Copyright file
├── Makefile                    # Build automation
├── Dockerfile                  # Container definition
├── renv.lock                   # Package dependency lock file
├── .Rprofile                   # renv activation + auto-snapshot
├── .gitignore                  # Git exclusions
├── .Rbuildignore               # R CMD build exclusions
├── R/                          # Reusable R functions
├── man/                        # Function documentation
├── tests/
│   └── tinytest.R              # Test runner
├── inst/
│   └── tinytest/
│       └── test-basic.R        # Example test
├── analysis/
│   ├── data/
│   │   ├── raw_data/           # Original untransformed data
│   │   └── derived_data/       # Processed data
│   ├── report/                 # Analysis reports
│   ├── figures/                # Generated plots
│   ├── tables/                 # Generated tables
│   └── scripts/                # Analysis scripts
├── docs/
│   └── ZZCOLLAB_USER_GUIDE.md  # This guide
├── vignettes/                  # Package vignettes
└── .github/
    └── workflows/              # GitHub Actions CI/CD
```

### Modular Setup

Instead of using a profile shortcut, you can build the workspace
incrementally:

```bash
zzc init                        # R package structure only
zzc renv                        # add renv (renv.lock, .Rprofile)
zzc docker                      # add Docker (Dockerfile)
zzc git                         # initialize git repository
zzc github                      # create GitHub repo and push
```

### Feature Wizard

`zzc init` runs a feature wizard whose checklist controls what is enabled at
setup. Two checkboxes are relevant here:

- **R language server in Docker image (in-container LSP)** -- default on,
  backed by the `languageserver` config key. Because zzcollab assumes no R on
  the host, the language server runs in the container, and a host editor (vim,
  VS Code) bridges its LSP client into it. Untick for REPL-only workflows.
- **Create remote now** -- default off. When ticked, the wizard creates the
  forge remote as part of setup. The `auto_github` config key (default
  `false`) pre-selects this checkbox; set it with
  `zzc config set auto_github true`. The item is hidden when the forge is
  `none`, the forge CLI is absent, or a confidential-repo guard denies remotes.
  `zzc github` walks up to the repository root before creating the remote, so
  it publishes the whole compendium rather than a subdirectory.

## Development Workflow

### Entering the Container

```bash
make r
```

This target:

1. Runs `zzcollab validate --fix --strict --verbose` to check
   package dependencies before starting.
2. Starts a Docker container with the project directory and renv
   cache mounted.
3. Launches R inside the container.

### Working Inside R

```r
devtools::load_all()            # load package functions
devtools::test()                # run tests
install.packages("newpkg")      # add a package
```

### Exiting

```r
q()
```

On exit, two things happen automatically:

1. **Auto-snapshot** (inside container): The `.Rprofile` `.Last()`
   hook runs `renv::snapshot(prompt = FALSE)` to update `renv.lock`.
2. **Post-session validation** (on host): The Makefile runs
   `zzcollab validate --fix --strict --verbose` to verify that
   DESCRIPTION and renv.lock are consistent with code usage.

### RStudio Server

```bash
make rstudio
```

Opens RStudio at `http://localhost:8787` (username: `rstudio`,
password: `rstudio`).

### Rebuilding the Image

After adding packages, rebuild so the Docker image includes them:

```bash
make docker-build               # content-addressable: skips if unchanged
make docker-rebuild             # force full rebuild (no cache)
```

## Package Management

### Two-Layer Model

**Layer 1 (Docker image):** Pre-installed packages from the selected
profile. These compile once at image build time and are shared by all
team members. Controlled by the team lead's profile choice.

**Layer 2 (renv.lock):** Dynamic packages added by any team member
inside the container. The lock file is the source of truth for
reproducibility, not the Docker image.

### Dependency Manifest: renv.lock + DESCRIPTION

Reproducibility rests on two complementary files. `renv.lock` pins the exact
package closure (versions); `DESCRIPTION` declares dependency roles. They are
complementary, not redundant. Role convention: packages used by code in `R/`
belong in `Imports`, and packages used only by `analysis/` (reports, scripts,
notebooks) belong in `Suggests`. Run `make snapshot` to grow both from the
built image, and see
[docs/package-placement-whitepaper.md](docs/package-placement-whitepaper.md)
for guidance on which packages belong in the Dockerfile versus `renv.lock`
versus `DESCRIPTION`.

### Adding Packages

```bash
make r
```

```r
install.packages("survival")
q()                             # auto-snapshot writes renv.lock
```

For GitHub packages:

```r
renv::install("user/package")
```

### Auto-Snapshot on Exit

Controlled by the environment variable `ZZCOLLAB_AUTO_SNAPSHOT`
(default: `true`). When R exits inside a container, the `.Last()`
function in `.Rprofile` runs `renv::snapshot(prompt = FALSE)`.

### Auto-Restore on Startup

Controlled by `ZZCOLLAB_AUTO_RESTORE` (default: `true`). When R
starts inside a container, `.Rprofile` runs
`renv::restore(prompt = FALSE)` to install any missing packages from
`renv.lock`.

### Auto-Initialize for New Projects

Controlled by `ZZCOLLAB_AUTO_INIT` (default: `true`). If no
`renv.lock` exists but a `DESCRIPTION` file is present, `.Rprofile`
initializes renv automatically.

### Host R Sessions

On the host (outside Docker), `.Rprofile` skips renv activation and
prints a reminder to use the container for reproducibility.

### Package Accumulation (Team)

```bash
# Alice adds a package
make r
> install.packages("tidymodels")
> q()                           # renv.lock now has tidymodels
git add renv.lock && git commit -m "Add tidymodels" && git push

# Bob pulls and adds another
git pull
make r                          # auto-restore gets tidymodels
> install.packages("sf")
> q()                           # renv.lock now has both
git add renv.lock && git commit -m "Add sf" && git push
```

### Validation

Pure-shell validation checks that all packages referenced in code are
listed in DESCRIPTION and renv.lock:

```bash
make check-renv                 # strict + auto-fix (recommended)
make check-renv-no-fix          # report only, no modifications
make check-renv-no-strict       # skip tests/ and vignettes/
make check-system-deps          # check system library requirements
```

## Team Collaboration

### Team Lead: Creating a Project

```bash
# One-time configuration
zzc config set dockerhub-account mylab
zzc config set github-account mylab

# Create project
mkdir genomics-study && cd genomics-study
zzc tidyverse

# Build and publish
make docker-build
zzc dockerhub                   # push image to Docker Hub
zzc github --private            # create private GitHub repo
```

### Team Member: Joining a Project

```bash
git clone https://github.com/mylab/genomics-study.git
cd genomics-study
make docker-build               # build from Dockerfile + renv.lock
make r                          # auto-restore runs on startup
```

### When to Update the Team Image

Rebuild and republish the Docker image when:

- The base R version changes.
- System libraries are needed (GDAL, PROJ, LaTeX).
- Core packages used by everyone should be pre-compiled.

Do not rebuild for individual analysis packages -- add those via
renv inside the container.

### Requesting System Dependencies

If a team member needs system libraries not in the Dockerfile:

```bash
# Option 1: open an issue
gh issue create --title "Add libgsl-dev for modeling"

# Option 2: submit a pull request
git checkout -b add-gsl
# edit Dockerfile to add the library
git add Dockerfile && git commit -m "Add GSL library"
gh pr create --title "Add GSL system library"
```

## Build System with Make

### Validation (no host R required)

```bash
make check-renv                 # strict + auto-fix + verbose
make check-renv-no-fix          # report only
make check-renv-no-strict       # skip tests/ and vignettes/
make check-renv-ci              # same as check-renv (CI compat)
make check-system-deps          # check Dockerfile system deps
```

### Main Workflow

```bash
make r                          # interactive R in container
make rstudio                    # RStudio Server on :8787
```

### Docker Build

```bash
make docker-build               # build image (content-addressable)
make docker-rebuild             # force rebuild without cache
make docker-build-log           # build with detailed logs
make docker-push-team           # tag and push to Docker Hub
```

### Docker Tasks

```bash
make docker-test                # run devtools::test() in container
make docker-check               # R CMD check in container
make docker-document            # devtools::document() in container
make docker-build-pkg           # R CMD build in container
make docker-vignettes           # build vignettes in container
make docker-render              # render analysis/report/report.Rmd
make docker-render-qmd          # render Quarto document
make docker-check-renv          # renv::status() in container
make docker-check-renv-fix      # renv::snapshot() in container
make docker-rstudio             # start RStudio Server
```

### Code Quality and Dependency Capture (in container)

```bash
make style                      # format R code with styler
make lint                       # lint R code with lintr
make snapshot                   # grow renv.lock + DESCRIPTION from image
```

`make style` and `make lint` require the code-quality feature (which installs
`styler` and `lintr` in the image). `make snapshot` runs `renv::hydrate()`,
`renv::snapshot(prompt = FALSE)`, and
`zzrenvcheck::check_packages(auto_fix = TRUE, strict = TRUE)` in the container;
run it before committing to capture code dependencies into the manifest.

### Native R (requires local R)

```bash
make document                   # devtools::document()
make build                      # R CMD build
make check                      # R CMD check --as-cran
make install                    # devtools::install()
make test                       # devtools::test()
make vignettes                  # devtools::build_vignettes()
make deps                       # devtools::install_deps()
```

### Cleanup

```bash
make clean                      # remove *.tar.gz and *.Rcheck
make docker-clean               # remove image and prune
make docker-disk-usage          # show Docker disk usage
make docker-prune-cache         # remove build cache
make docker-prune-all           # deep clean all unused Docker
```

## Configuration System

### Hierarchy

Settings at more specific levels override broader defaults:

1. Command-line flags (highest priority)
2. Environment variables
3. Project config (`./zzcollab.yaml`)
4. User config (`~/.zzcollab/config.yaml`)
5. Built-in defaults (lowest priority)

### Commands

```bash
zzc config init                 # create ~/.zzcollab/config.yaml
zzc config set KEY VALUE        # set user-global value
zzc config get KEY              # get value (merged hierarchy)
zzc config list                 # show all configuration
zzc config set-local KEY VALUE  # set project-local value
zzc config get-local KEY        # get project-local value
zzc config list-local           # show project config only
zzc config validate             # validate YAML syntax
zzc config path                 # show config file paths
```

### Common Configuration

```bash
zzc config init
zzc config set dockerhub-account mylab
zzc config set github-account myusername
zzc config set profile-name tidyverse
zzc config set author-name "Jane Doe"
zzc config set author-email "jane@example.edu"
```

### Key Reference

**Author:**
`author-name`, `author-email`, `author-orcid`,
`author-affiliation`, `author-affiliation-full`, `author-roles`

**Docker:**
`dockerhub-account`, `profile-name`, `r-version`,
`docker-registry` (default: docker.io),
`docker.platform` (default: linux/amd64),
`languageserver` (default: true) -- install the R language server in the
Docker image for in-container LSP completion and diagnostics; set false for
REPL-only workflows

**GitHub:**
`github-account`, `github-default-visibility` (default: private),
`github-default-branch` (default: main)

**R Package:**
`min-r-version` (default: 4.1.0),
`vignette-builder` (default: knitr)

**Code Style:**
`line-length` (default: 78), `use-native-pipe` (default: true),
`assignment` (default: arrow), `naming-convention`

**License:**
`license-type` (default: GPL-3), `license-year`, `license-holder`

**CI/CD:**
`cicd.r-versions`, `cicd.run-coverage` (default: true),
`cicd.coverage-threshold` (default: 80)

### Project-Level Configuration

Create `zzcollab.yaml` in the project root to override user defaults
for a specific project:

```yaml
defaults:
  profile_name: tidyverse
  dockerhub_account: mylab
  github_account: mylab

author:
  name: "Jane Doe"
  email: "jane@example.edu"
```

## GitHub Actions CI/CD

### Provided Workflow

The `r-package.yml` workflow runs on push to `main`/`master` and on
pull requests:

1. Checks out code.
2. Sets up R with `r-lib/actions`.
3. Installs package dependencies.
4. Validates the dependency manifest (renv.lock + DESCRIPTION): a
   'Validate dependency manifest (renv.lock + DESCRIPTION)' step runs
   `zzrenvcheck::check_packages` and fails the build when code references a
   package that is not declared in `DESCRIPTION` or not locked in `renv.lock`.
5. Runs `R CMD check --as-cran`.
6. Calculates code coverage.

The workflow tests across a matrix of R versions and platforms
(Ubuntu, macOS, Windows).

### Repository Secrets

For automated Docker Hub publishing, add these secrets in GitHub
(Settings > Secrets and variables > Actions):

```
DOCKERHUB_USERNAME: your-dockerhub-username
DOCKERHUB_TOKEN:    your-dockerhub-access-token
```

Create an access token at https://hub.docker.com/settings/security.

## GitLab support

zzcollab supports GitLab as an alternative to GitHub. The active forge is
a single choice, set once:

```
zzc config set forge gitlab
zzc config set gitlab-account mylab
zzc config set gitlab-host gitlab.example.edu   # self-hosted only
```

The forge can also be chosen interactively in `zzc toggle` (the forge
picker), and is the first decision in the feature wizard.

With `forge=gitlab`, the framework adapts as follows:

- **CI**: a single `.gitlab-ci.yml` replaces the two GitHub Actions
  workflows. It self-adapts to the backend (Nix flake, Docker, renv, or
  DESCRIPTION) and runs a check stage and a path-filtered render stage,
  mirroring the GitHub pipeline. Install or remove it with
  `zzc add cicd` / `zzc rm cicd`, or via the `ci` feature in `zzc toggle`.
- **Remote repository**: `zzc gitlab` (counterpart to `zzc github`) uses
  the `glab` CLI to create the project and push, honouring `gitlab-host`
  for self-hosted instances. Visibility is `--private` (default),
  `--public`, or `--internal`.
- **Container registry**: pushes default to the GitLab Container Registry
  (`registry.gitlab.com`, or `registry.<host>` for self-hosted), whose CI
  authentication is provided automatically by GitLab's `$CI_REGISTRY`
  variables. Override with `zzc config set docker-registry <host>`. Push
  with `zzc push` (the registry-aware command; `zzc dockerhub` is a
  back-compat alias).
- **Cloud launch**: `zzc cloud` installs a GitLab Workspaces devfile
  (`.devfile.yaml`) instead of the Codespaces devcontainer. Force either
  with `zzc cloud --platform workspace` or `--platform devcontainer`.

GitLab integration requires the `glab` CLI for repository creation
(`zzc gitlab`); CI, registry, and Workspaces configuration are generated
without it.

## Troubleshooting

### Docker Problems

```
Error: Docker daemon not running
Solution: Start Docker Desktop

Error: No space left on device
Solution: make docker-clean && docker system prune
         or: make docker-prune-all
```

### Package Issues

```
Error: Package 'xyz' not available
Solution: Check the package name; try renv::install("xyz")

Error: Dependencies not synchronized
Solution: make check-renv

Error: renv cache issues
Solution: renv::restore() then renv::rebuild() if needed
```

### Dockerfile Missing

```
Error: No Dockerfile found - workspace not initialized
Solution: Run zzc docker (or zzc tidyverse for full setup)
```

### Team Collaboration

```
Error: Unable to pull team/project:latest
Solution: Check Docker Hub permissions; verify team lead pushed
         the image with: zzc dockerhub

Error: Package versions differ between team members
Solution: All members run: git pull && make docker-build && make r
```

### Profile or Bundle Not Found

```
Error: Unknown profile 'xyz'
Solution: zzc list profiles

Error: Missing system dependencies for R package
Solution: make check-system-deps
```

## Platform-Specific Notes

### ARM64 (Apple Silicon)

**Compatible profiles (native ARM64):**

- `minimal` (rocker/r-ver)
- `rstudio` (rocker/rstudio)

**AMD64-only profiles (run under emulation):**

- `tidyverse` (rocker/tidyverse)
- `publishing` (rocker/verse)

**Specialized base images (run under emulation on ARM64):**

- rocker/shiny base image (Shiny applications)

ZZCOLLAB automatically applies `--platform linux/amd64` when building
on ARM64 hosts for images that require emulation.

### Platform Configuration

The Docker build/run platform is controlled by Docker's own environment
variable (zzcollab does not store it in config):

```bash
export DOCKER_DEFAULT_PLATFORM=linux/amd64   # force AMD64 (e.g. rocker/verse on ARM)
export DOCKER_DEFAULT_PLATFORM=linux/arm64   # force ARM64
unset DOCKER_DEFAULT_PLATFORM                 # use the host architecture (default)
```

## CLI Reference

### Commands

```bash
zzc <profile>                   # create or switch profile
zzc init                        # create R package structure
zzc renv                        # set up renv
zzc docker [OPTIONS]            # generate/build Dockerfile
zzc rebuild [OPTIONS]           # rebuild Docker image
zzc git                         # initialize git
zzc github [--public|--private] # create GitHub repository
zzc dockerhub [--tag TAG]       # push image to Docker Hub
zzc validate [OPTIONS]          # check project structure
zzc doctor [DIR] [--scan DIR]   # detect outdated templates
zzc update [DIR] [--dry-run] [--force]  # regenerate managed files to current version
zzc config <subcommand>         # configuration management
zzc list [profiles|libs|pkgs]   # list available options
zzc rm <feature> [-f]           # remove docker|renv|git|all
zzc help [topic]                # show help
```

### Global Flags

```bash
-v, --verbose                   # verbose output
-q, --quiet                     # errors only
-y, --yes                       # accept all defaults
-h, --help                      # show usage
--version                       # show version
--no-build                      # skip Docker build prompts
```

### Help Topics

```bash
zzc help quickstart             # getting started
zzc help workflow               # daily development
zzc help team                   # team collaboration
zzc help config                 # configuration system
zzc help profiles               # Docker profiles
zzc help docker                 # Docker architecture
zzc help renv                   # package management
zzc help cicd                   # CI/CD automation
zzc help doctor                 # workspace health checks
zzc help rm                     # removing features
zzc help troubleshoot           # common issues
zzc help options                # all command-line options
```
