" set leader key
nnoremap <SPACE> <Nop>
let mapleader=" "

syntax enable                           " Enables syntax highlighing
filetype plugin on                      " Syntax highlighting and comments from file type
filetype indent on                      " indentation from filetype
"set nowrap                              " Display long lines as just one line
set encoding=utf-8                      " The encoding displayed
set pumheight=10                        " Makes popup menu smaller
setglobal fileencoding=utf-8            " The encoding written to file
set ruler   		                        " Show the cursor position all the time
set iskeyword+=-                      	" Treat dash separated words as a word text object"
set mouse=a                             " Enable your mouse
set splitbelow                          " Horizontal splits will automatically be below
set splitright                          " Vertical splits will automatically be to the right
"set t_Co=256                            " Support 256 colors
"set conceallevel=0                      " So that I can see `` in markdown files
set colorcolumn=100                     " Show colored column at 100 characters
set tabstop=2                           " Insert 2 spaces for a tab
set shiftwidth=2                        " Change the number of space characters inserted for indentation
"set softtabstop=2                       " Not sure what this does
set smarttab                            " Makes tabbing smarter will realize you have 2 vs 4
set expandtab                           " Converts tabs to spaces
set smartindent                         " Makes indenting smart
set autoindent                          " Good auto indent
set laststatus=2                        " Always display the status line
set number                              " Line numbers
set showmatch                           " Colorizes search, and shows closest match in a different color
set hlsearch                            " Highlight all matched strings during search
set incsearch                           " Makes the above two options even more awesome 
set ignorecase                          " Ignore case when searching ...
set smartcase                           " ... Except when using capital letters
set relativenumber                      " Show relative line numbers
set wildmode=longest,list,full          " Autocompletion
"autocmd FileType * setlocal formatoptions-=c formatoptions-=r formatoptions-=o " disable automatic comments on newline
set cursorline                          " Enable highlighting of the current line
set background=dark                     " Tell vim what the background color looks like
set showtabline=2                       " Always show tabs
set noshowmode                          " We don't need to see things like -- INSERT -- anymore
set updatetime=300                      " Faster completion
set timeoutlen=500                      " By default timeoutlen is 1000 ms
set formatoptions-=cro                  " Stop newline continution of comments
set clipboard=unnamedplus               " Copy paste between vim and everything else
set autoread                            " Watch for file changes
"set autochdir                           " Your working directory will always be the same as your working directory
set showcmd                             " show leader key bottom right corner when pressed
"set undofile                            " creates <FILENAME>.un~ files which allow you to undo old (saved and closed) actions
set gdefault                            " automatically adds g to :%s/a/b/g when search+replacing

au! BufWritePost $MYVIMRC source %      " Auto source when writing to init.vim, alternatively you can run :source $MYVIMRC
