FROM fedora:44@sha256:6c75d5bf57cb0fa5aa4b92c6a83c86c791644496d9ac230de7711f5b8ec3b898

ARG HOST_UID=1000
ARG HOST_GID=1000
ARG USERNAME=dev
ARG FNM_VERSION=v1.39.0
ARG NODE_VERSION=22
ARG HERDR_VERSION=v0.7.1

RUN dnf install -y sudo unzip zsh git curl gh vim jq gawk && dnf clean all

RUN if getent group ${HOST_GID} >/dev/null; then \
        GROUPNAME=$(getent group ${HOST_GID} | cut -d: -f1); \
    else \
        GROUPNAME=${USERNAME}; \
        groupadd -g ${HOST_GID} ${GROUPNAME}; \
    fi \
    && useradd -u ${HOST_UID} -g ${HOST_GID} -m -s /usr/bin/zsh ${USERNAME} \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

# oh-my-zsh baked into /etc/skel
RUN git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git /etc/skel/.oh-my-zsh \
    && cp /etc/skel/.oh-my-zsh/templates/zshrc.zsh-template /etc/skel/.zshrc \
    && rm -rf /etc/skel/.oh-my-zsh/.git

# fnm installed system-wide
RUN ARCH=$(uname -m) \
    && case "$ARCH" in \
         aarch64) FNM_ASSET=fnm-arm64.zip ;; \
         x86_64)  FNM_ASSET=fnm-linux.zip ;; \
         armv7l)  FNM_ASSET=fnm-arm32.zip ;; \
         *) echo "unsupported arch: $ARCH" >&2 && exit 1 ;; \
       esac \
    && curl -fsSL -o /tmp/fnm.zip "https://github.com/Schniz/fnm/releases/download/${FNM_VERSION}/${FNM_ASSET}" \
    && unzip -q /tmp/fnm.zip -d /usr/local/bin \
    && chmod +x /usr/local/bin/fnm \
    && rm /tmp/fnm.zip

RUN echo 'eval "$(fnm env --use-on-cd --shell bash)"' >> /etc/skel/.bashrc \
    && echo 'eval "$(fnm env --use-on-cd --shell zsh)"' >> /etc/skel/.zshrc

# [sandbox] prompt tag
RUN { \
      echo ''; \
      echo 'if [ -f /.dockerenv ]; then'; \
      echo '  PROMPT="%F{243}[sandbox]%f ${PROMPT}"'; \
      echo 'fi'; \
    } >> /etc/skel/.zshrc

# Some host terminals lack terminfo entries here; force known-good values.
RUN echo 'export TERM=xterm-256color' >> /etc/skel/.bashrc \
    && echo 'export COLORTERM=truecolor' >> /etc/skel/.bashrc \
    && echo 'export TERM=xterm-256color' >> /etc/skel/.zshrc \
    && echo 'export COLORTERM=truecolor' >> /etc/skel/.zshrc

# default Node version pre-installed into /etc/skel
RUN mkdir -p /etc/skel/.local/share/fnm \
    && FNM_DIR=/etc/skel/.local/share/fnm /usr/local/bin/fnm install ${NODE_VERSION} \
    && FNM_DIR=/etc/skel/.local/share/fnm /usr/local/bin/fnm default ${NODE_VERSION}

# bun baked into /etc/skel
RUN HOME=/etc/skel bash -c 'curl -fsSL https://bun.sh/install | bash' \
    && echo 'export BUN_INSTALL="$HOME/.bun"' >> /etc/skel/.bashrc \
    && echo 'export PATH="$BUN_INSTALL/bin:$PATH"' >> /etc/skel/.bashrc \
    && echo 'export BUN_INSTALL="$HOME/.bun"' >> /etc/skel/.zshrc \
    && echo 'export PATH="$BUN_INSTALL/bin:$PATH"' >> /etc/skel/.zshrc

# herdr (herdr.dev)
RUN ARCH=$(uname -m) \
    && case "$ARCH" in \
         aarch64) HERDR_ASSET=herdr-linux-aarch64 ;; \
         x86_64)  HERDR_ASSET=herdr-linux-x86_64 ;; \
         *) echo "unsupported arch: $ARCH" >&2 && exit 1 ;; \
       esac \
    && curl -fsSL -o /usr/local/bin/herdr "https://github.com/ogulcancelik/herdr/releases/download/${HERDR_VERSION}/${HERDR_ASSET}" \
    && chmod +x /usr/local/bin/herdr

COPY herdr-config.toml /etc/skel/.config/herdr/config.toml

# Claude Code CLI
RUN mkdir -p /var/lib/claude-ephemeral \
    && HOME=/var/lib/claude-ephemeral bash -c 'curl -fsSL https://claude.ai/install.sh | bash' \
    && chown -R ${HOST_UID}:${HOST_GID} /var/lib/claude-ephemeral

# Claude Code settings
RUN mkdir -p /var/lib/claude-ephemeral/.claude \
    && printf '%s\n' \
       '{' \
       '  "theme": "dark",' \
       '  "verbose": true,' \
       '  "autoCompactEnabled": false,' \
       '  "spinnerTipsEnabled": false,' \
       '  "alwaysThinkingEnabled": true,' \
       '  "skipDangerousModePermissionPrompt": true,' \
       '  "permissions": {' \
       '    "defaultMode": "dontAsk"' \
       '  },' \
       '  "statusLine": {' \
       '    "type": "command",' \
       '    "command": "~/.claude/statusline.sh"' \
       '  },' \
       '  "attribution": {' \
       '    "commit": "",' \
       '    "pr": ""' \
       '  }' \
       '}' > /var/lib/claude-ephemeral/.claude/settings.json \
    && chown -R ${HOST_UID}:${HOST_GID} /var/lib/claude-ephemeral/.claude

# Workspace trust: statusLine/hooks need it; skip-permissions hides the dialog.
RUN printf '%s\n' \
       '{' \
       '  "projects": {' \
       "    \"/home/${USERNAME}/Code\": {" \
       '      "hasTrustDialogAccepted": true' \
       '    }' \
       '  }' \
       '}' > /var/lib/claude-ephemeral/.claude.json \
    && chown ${HOST_UID}:${HOST_GID} /var/lib/claude-ephemeral/.claude.json

# Status line script (referenced by settings.json)
COPY --chown=${HOST_UID}:${HOST_GID} statusline.sh /var/lib/claude-ephemeral/.claude/statusline.sh
RUN chmod +x /var/lib/claude-ephemeral/.claude/statusline.sh

# herdr <-> Claude integration (agent-state hook: sidebar state, auto-resume)
RUN HOME=/var/lib/claude-ephemeral herdr integration install claude \
    && chown -R ${HOST_UID}:${HOST_GID} /var/lib/claude-ephemeral/.claude

# Baked skills; the entrypoint seeds missing ones into the skills dir
COPY skills/ /usr/share/claude-skills/

# 'claude' wrapper: $HOME redirected to the scratch dir
RUN { \
      echo ''; \
      echo 'claude() { IS_DEMO=0 HOME=/var/lib/claude-ephemeral /var/lib/claude-ephemeral/.local/bin/claude --dangerously-skip-permissions --effort max "$@"; }'; \
    } >> /etc/skel/.bashrc \
    && { \
      echo ''; \
      echo 'claude() { IS_DEMO=0 HOME=/var/lib/claude-ephemeral /var/lib/claude-ephemeral/.local/bin/claude --dangerously-skip-permissions --effort max "$@"; }'; \
    } >> /etc/skel/.zshrc

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Rebake home from the finished skel (useradd -m ran before skel was populated)
RUN rm -rf /home/${USERNAME} \
    && cp -rT /etc/skel /home/${USERNAME} \
    && chown -R ${HOST_UID}:${HOST_GID} /home/${USERNAME}

# docker exec sets no SHELL; herdr falls back to sh without it
ENV SHELL=/usr/bin/zsh

USER ${USERNAME}
WORKDIR /home/${USERNAME}/Code
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/bin/zsh"]
