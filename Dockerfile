FROM fedora:44@sha256:6c75d5bf57cb0fa5aa4b92c6a83c86c791644496d9ac230de7711f5b8ec3b898

ARG HOST_UID=1000
ARG HOST_GID=1000
ARG USERNAME=dev
ARG NODE_VERSION=22

RUN dnf install -y sudo unzip zsh git curl gh vim jq gawk rsync && dnf clean all

RUN if getent group ${HOST_GID} >/dev/null; then \
        GROUPNAME=$(getent group ${HOST_GID} | cut -d: -f1); \
    else \
        GROUPNAME=${USERNAME}; \
        groupadd -g ${HOST_GID} ${GROUPNAME}; \
    fi \
    && useradd -u ${HOST_UID} -g ${HOST_GID} -m -s /usr/bin/zsh ${USERNAME} \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

# oh-my-zsh
RUN git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git /home/${USERNAME}/.oh-my-zsh \
    && cp /home/${USERNAME}/.oh-my-zsh/templates/zshrc.zsh-template /home/${USERNAME}/.zshrc \
    && rm -rf /home/${USERNAME}/.oh-my-zsh/.git

# fnm (official installer); --skip-shell: $SHELL is unset in docker build (the
# script would exit 1) and shellrc.sh wires it up with --use-on-cd instead
RUN HOME=/home/${USERNAME} bash -c 'curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell'

# default Node version pre-installed
RUN FNM_DIR=/home/${USERNAME}/.local/share/fnm /home/${USERNAME}/.local/share/fnm/fnm install ${NODE_VERSION} \
    && FNM_DIR=/home/${USERNAME}/.local/share/fnm /home/${USERNAME}/.local/share/fnm/fnm default ${NODE_VERSION}

# bun (official installer; rc wiring lives in shellrc.sh)
RUN HOME=/home/${USERNAME} bash -c 'curl -fsSL https://bun.com/install | bash'

# herdr (herdr.dev); system-wide so the root-run integration step finds it
RUN HERDR_INSTALL_DIR=/usr/local/bin sh -c 'curl -fsSL https://herdr.dev/install.sh | sh'

COPY config/herdr-config.toml /home/${USERNAME}/.config/herdr/config.toml

# Shared shell config: TERM, fnm/bun/claude PATH wiring, claude wrapper, prompt tag
COPY config/shellrc.sh /home/${USERNAME}/.config/shellrc.sh
RUN echo 'source ~/.config/shellrc.sh' >> /home/${USERNAME}/.bashrc \
    && echo 'source ~/.config/shellrc.sh' >> /home/${USERNAME}/.zshrc

# GitHub over https: ssh remotes rewritten, GH_TOKEN as credential (no ssh key)
RUN printf '%s\n' \
       '[url "https://github.com/"]' \
       '  insteadOf = git@github.com:' \
       '  insteadOf = ssh://git@github.com/' \
       '[credential "https://github.com"]' \
       '  helper = !gh auth git-credential' \
       '[credential "https://gist.github.com"]' \
       '  helper = !gh auth git-credential' \
       > /home/${USERNAME}/.gitconfig

# Baked skills; the entrypoint seeds missing ones into the skills dir
COPY skills/ /usr/share/claude-skills/

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Claude Code CLI
RUN HOME=/home/${USERNAME} bash -c 'curl -fsSL https://claude.ai/install.sh | bash'

# Claude Code settings (herdr integration below appends its hook here)
COPY config/claude-settings.json /home/${USERNAME}/.claude/settings.json

# Workspace trust gates statusLine/hooks (skip-permissions does NOT grant it);
# worktrees path pinned in herdr-config.toml
RUN printf '%s\n' \
       '{' \
       '  "projects": {' \
       "    \"/home/${USERNAME}/Code\": {" \
       '      "hasTrustDialogAccepted": true' \
       '    },' \
       "    \"/home/${USERNAME}/.herdr/worktrees\": {" \
       '      "hasTrustDialogAccepted": true' \
       '    }' \
       '  }' \
       '}' > /home/${USERNAME}/.claude.json

# Status line script
COPY config/statusline.sh /home/${USERNAME}/.claude/statusline.sh
RUN chmod +x /home/${USERNAME}/.claude/statusline.sh

# herdr <-> Claude integration (registers an absolute hook path)
RUN HOME=/home/${USERNAME} herdr integration install claude

# Build steps ran as root; hand the home to the user. ~/Code made here — nothing
# mounts it now, and the runtime would create the workdir root-owned.
RUN mkdir -p /home/${USERNAME}/Code \
    && chown -R ${HOST_UID}:${HOST_GID} /home/${USERNAME}

# docker exec sets no SHELL; herdr falls back to sh without it
ENV SHELL=/usr/bin/zsh

USER ${USERNAME}
WORKDIR /home/${USERNAME}/Code
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/bin/zsh"]
