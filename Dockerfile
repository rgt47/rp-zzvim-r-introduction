# syntax=docker/dockerfile:1.4
# zzcollab Dockerfile v0.3.0

# BASE_IMAGE is parsed out of this file by the project Makefile ('make r'
# derives the profile label from it); keep it even though the FROM below uses
# a fully-substituted literal and does not reference the ARG.
ARG BASE_IMAGE=rocker/tidyverse

FROM rocker/tidyverse:4.6.0@sha256:d00d68ecb138a9f677125f453dd46fd8bbf914866c1cd01c27547403ccc393ce

# OCI image labels for reproducibility provenance and tooling integration.
# base_digest records the resolved sha256 of the rocker base at build time;
# ppm_snapshot records the dated PPM URL used to pin package binaries.
LABEL org.opencontainers.image.created="2026-08-28T19:00:22Z" \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      zzcollab.template.version="0.3.0" \
      zzcollab.r.version="4.6.0" \
      zzcollab.base.image="rocker/tidyverse:4.6.0" \
      zzcollab.base.digest="sha256:d00d68ecb138a9f677125f453dd46fd8bbf914866c1cd01c27547403ccc393ce" \
      zzcollab.ppm.snapshot="2026-08-28" \
      zzcollab.install.mode="renv"

ARG USERNAME=analyst
ARG DEBIAN_FRONTEND=noninteractive

# RENV_PATHS_LIBRARY is outside the project bind-mount so the baked library
# is not shadowed at runtime. ZZCOLLAB_AUTO_RESTORE=false disables the
# startup restore so the image library is authoritative.
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 TZ=UTC \
    RENV_PATHS_LIBRARY=/opt/renv/library \
    RENV_PATHS_CACHE=/opt/renv/cache \
    RENV_CONFIG_REPOS_OVERRIDE="https://packagemanager.posit.co/cran/__linux__/noble/2026-08-28" \
    ZZCOLLAB_CONTAINER=true \
    ZZCOLLAB_INSTALL_MODE=renv \
    ZZCOLLAB_AUTO_RESTORE=false

# No additional system dependencies required

# Configure R to use Posit Package Manager for pre-compiled binaries
RUN echo 'options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/2026-08-28"))' \
        >> /usr/local/lib/R/etc/Rprofile.site && \
    echo 'options(HTTPUserAgent = sprintf("R/%s R (%s)", getRversion(), paste(getRversion(), R.version["platform"], R.version["arch"], R.version["os"])))' \
        >> /usr/local/lib/R/etc/Rprofile.site

# Install R dev tooling only (languageserver/styler/lintr, config-gated;
# never in renv.lock). Project packages come from renv::restore(), not here.
RUN R -e "install.packages(c('languageserver'), Ncpus = max(1L, parallel::detectCores()))"

# Dependency install (self-adapting, INSTALL_MODE=renv). The block
# below is emitted by generation-time branch on renv.lock presence. In renv
# mode, tools_install above runs BEFORE renv::init so IDE tools are in the
# system library; renv::init then activates renv and routes later installs to
# RENV_PATHS_LIBRARY.
RUN R -e "install.packages('renv')"
# 0777 so the non-root run user can hydrate/snapshot into the library (F-2);
# single-user research container, so world-writable here is acceptable.
RUN mkdir -p /opt/renv/library /opt/renv/cache && chmod 777 /opt/renv/library /opt/renv/cache
COPY renv.lock renv.lock
# RENV_LOCK_HASH is passed by the builder as a digest of renv.lock. Declaring
# it here and referencing it in the RUN below makes the restore layer's cache
# key depend on the lockfile content, so renv::restore() re-runs whenever
# renv.lock changes. This guards against BuildKit serving a stale restore
# layer, which would otherwise bake a library that silently diverges from the
# lockfile (and from the image's content-addressable hash label).
ARG RENV_LOCK_HASH=unknown
# renv::init creates the platform-specific library directory structure that
# renv::restore() requires to link packages from the cache.
RUN echo "renv.lock hash: ${RENV_LOCK_HASH}" &&     R -e "renv::init(bare=TRUE, force=TRUE, restart=FALSE); renv::restore(exclude = 'renv')"

# Make the baked renv library discoverable to R sessions started OUTSIDE the
# project root. 'quarto render analysis/report' (archetype: book) spawns R with
# the working directory inside analysis/report/, which has no project .Rprofile to
# source renv/activate.R, so renv never puts /opt/renv/library on .libPaths().
# Rprofile.site is sourced regardless of cwd, so add the baked library here.
# Guarded by dir.exists, so non-renv (e.g. minimal) images are unaffected. Does
# not touch 'Rscript --vanilla' sessions (they skip the site file); the render
# CI heredoc keeps its own .libPaths() shim for that reason.
RUN echo 'local({ lib <- Sys.glob(file.path(Sys.getenv("RENV_PATHS_LIBRARY", "/opt/renv/library"), "*", "*", "*"))[1]; if (length(lib) == 1L && !is.na(lib) && nzchar(lib) && dir.exists(lib)) .libPaths(unique(c(lib, .libPaths()))) })' \
        >> /usr/local/lib/R/etc/Rprofile.site

# Install zzrenvcheck as a validation tool (system library, outside project renv).
# Installed post-build via make install-zzrenvcheck to avoid GitHub/network
# issues during docker build on cloud-mounted filesystems.


# Create non-root user, in the 'staff' group. rocker/verse owns its TeX tree
# (/opt/texlive, /usr/local/texlive) as root:staff and makes it group-writable,
# so a render that installs LaTeX packages at run time (tinytex) needs the run
# user to be in 'staff'; otherwise tlmgr/fmtutil fail with permission errors.
# Own the renv library AND cache (populated as root by the restore above) so the
# run user can hydrate/snapshot into them; the earlier chmod is non-recursive
# and predates the restore, so it does not cover the package subdirectories (F-2).
RUN useradd --create-home --shell /bin/bash --groups staff ${USERNAME} && \
    chown -R ${USERNAME}:${USERNAME} /usr/local/lib/R/site-library /opt/renv

USER ${USERNAME}
WORKDIR /home/${USERNAME}/project

CMD ["R", "--quiet"]
