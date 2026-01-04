#    _               _
#   | |__   __ _ ___| |__  _ __ ___
#   | '_ \ / _` / __| '_ \| '__/ __|
#  _| |_) | (_| \__ \ | | | | | (__
# (_)_.__/ \__,_|___/_| |_|_|  \___|
#

[[ $- != *i* ]] && return                                                                 # if not running interactively, don't do anything

export PATH="$HOME/.local/bin:$PATH"

# SETUP
export EDITOR="nvim"
export ICAROOT="/opt/Citrix/ICAClient"
export TERM="xterm-256color"
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'    # GCC warnings and errors colorized
export MANPAGER="nvim +Man!"                                                              # neovim as manpager
shopt -s histappend			                                                                  # append to the history file, don't overwrite it
shopt -s checkwinsize	                                                                    # update $LINES and $COLUMNS depending on window size after each command
shopt -s cdspell                                                                          # autocorrect cd spelling errors
shopt -s cmdhist                                                                          # save multi-line commands in history as single-line
shopt -s expand_aliases                                                                   # expand aliases
HISTCONTROL=ignoreboth	                                                                  # don't put duplicate lines or lines starting with space in history.
HISTSIZE=HISTFILESIZE=                                                                    # infinite history and history file size
PROMPT_COMMAND='echo -ne "\033]0;${USER}@${HOSTNAME}: ${PWD}/\007"'                       # terminal window title
#PS1='\w/ > '							                                                                # prompt: dir>
force_color_prompt=yes	                                                                  # use a colored prompt

# FUNCTIONS
ex () {                                                                                   # unpack (almost) everything with ex <file>
  if [ -z "$1" ]; then
    echo "Usage: ex <path/file_name>.<zip|rar|bz2|gz|tar|tbz2|tgz|Z|7z|xz|ex|tar.bz2|tar.gz|tar.xz>"
    echo "       extract <path/file_name_1.ext> [path/file_name_2.ext] [path/file_name_3.ext]"
  else
    for n in "$@"
    do
      if [ -f "$n" ] ; then
        case "${n%,}" in
         *.cbt|*.tar.bz2|*.tar.gz|*.tar.xz|*.tbz2|*.tgz|*.txz|*.tar)
                         tar xvf "$n"       ;;
            *.lzma)      unlzma ./"$n"      ;;
            *.bz2)       bunzip2 ./"$n"     ;;
            *.cbr|*.rar)       unrar x -ad ./"$n" ;;
            *.gz)        gunzip ./"$n"      ;;
            *.cbz|*.epub|*.zip)       unzip ./"$n"       ;;
            *.z)         uncompress ./"$n"  ;;
            *.7z|*.arj|*.cab|*.cb7|*.chm|*.deb|*.dmg|*.iso|*.lzh|*.msi|*.pkg|*.rpm|*.udf|*.wim|*.xar)
                         7z x ./"$n"        ;;
            *.xz)        unxz ./"$n"        ;;
            *.exe)       cabextract ./"$n"  ;;
            *.cpio)      cpio -id < ./"$n"  ;;
            *.cba|*.ace)      unace x ./"$n"      ;;
          *)		
            echo "ex: '$n' - unknown archive format"
            return 1
            ;;
        esac
    else
      echo "'$n' - file does not exist"
    fi
  done
fi
}

# ALIASES
alias upgrade='emerge --update --deep @world'		                                          # update system packages
alias ..='cd ..'                                                                          # removes the need of typing cd before ...
alias cp='cp -i'						                                                              # confirm before overwriting when copying
alias df='df -h'						                                                              # human-readable sizes
alias free='free -m'						                                                          # human readable sizes
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias ls='ls --color=auto'
alias ll='ls --color=auto -ahlrt'
alias nano='nvim'
alias c='code'
alias v='nvim'
alias n='nvim'
alias htop='btop'
alias sudo='doas'

