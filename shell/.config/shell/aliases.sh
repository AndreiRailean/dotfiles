# Aliases — harmless in non-interactive shells, so defined unconditionally.

# ls — prefer eza (icons, git status, tree); fall back to plain ls on bare
# machines. --icons=auto only draws icons to a terminal, not into pipes.
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --group-directories-first --icons=auto'
  alias ll='eza -l  --git --group-directories-first --icons=auto'
  alias la='eza -la --git --group-directories-first --icons=auto'
  alias lt='eza --tree --level=2 --group-directories-first --icons=auto'
  alias l='eza -1 --group-directories-first --icons=auto'
else
  # colour flag differs: GNU coreutils (Linux/WSL) vs BSD (macOS)
  if ls --color=auto >/dev/null 2>&1; then
    alias ls='ls --color=auto'
  else
    alias ls='ls -G'
  fi
  alias ll='ls -alF'
  alias la='ls -A'
  alias l='ls -CF'
fi

alias grep='grep --color=auto'

# bat — cat with syntax highlighting. Debian/Ubuntu ships the binary as
# `batcat`; alias `bat` to it there so `bat` works everywhere. Use cat as a
# drop-in (--paging=never keeps cat's dump-and-exit behaviour). When piped,
# bat auto-disables decorations, so `cat file | ...` still behaves like cat.
#
# `less` is aliased to bat too, to keep the muscle memory — --paging=always so
# short files still open in the pager the way real less does. bat runs less
# underneath, so /, g/G and q all still work. It does NOT understand less's own
# flags (+F to follow, -N, -S): use `command less` for those.
if command -v batcat >/dev/null 2>&1; then
  alias bat='batcat'
  alias cat='batcat --paging=never'
  alias less='batcat --paging=always'
elif command -v bat >/dev/null 2>&1; then
  alias cat='bat --paging=never'
  alias less='bat --paging=always'
fi

# fd — friendlier find. Debian/Ubuntu ships the binary as `fdfind`, so alias
# `fd` to it there (elsewhere fd is already the real command).
if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
  alias fd='fdfind'
fi

# nvim — most distros ship a preinstalled vim, so `vim` keeps resolving to it
# even after neovim is installed. Point the vim names at nvim whenever it's
# there; on a machine without nvim these are skipped and real vim still works.
# EDITOR/VISUAL (env.sh) cover non-interactive callers like git.
if command -v nvim >/dev/null 2>&1; then
  alias vim='nvim'
  alias vi='nvim'
  alias vimdiff='nvim -d'
fi

# cd shortcuts
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# git — mirrors the aliases in ~/.config/git/config
alias g='git'
alias gs='git s'
alias gd='git d'
alias lg='git lg'
