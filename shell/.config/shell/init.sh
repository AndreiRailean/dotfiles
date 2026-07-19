# ~/.config/shell/init.sh — cross-shell entrypoint
#
# Sourced by both ~/.bashrc and ~/.zshrc. Written in POSIX sh so bash and
# zsh can source it verbatim; anything shell-specific lives behind a
# runtime check ($BASH_VERSION / $ZSH_VERSION) inside the fragments below.

_shell_dir="${XDG_CONFIG_HOME:-$HOME/.config}/shell"

# Order matters: env sets XDG/vars, path builds PATH, tools may extend PATH,
# prompt runs last so starship is on PATH by the time it initialises.
for _f in env path aliases tools prompt; do
  [ -r "$_shell_dir/$_f.sh" ] && . "$_shell_dir/$_f.sh"
done
unset _f

# Per-machine overrides — never committed. See local.sh.example.
[ -r "$_shell_dir/local.sh" ] && . "$_shell_dir/local.sh"

unset _shell_dir
