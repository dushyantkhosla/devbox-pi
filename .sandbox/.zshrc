export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="agnoster"
plugins=(git colorize history-substring-search themes z)
source "$ZSH/oh-my-zsh.sh"
prompt_context(){}
[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
