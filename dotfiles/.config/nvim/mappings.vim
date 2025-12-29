" :verbose map <leader> to check where leader-key has been mapped
" :map to check all mappings

" Force a Vim-noob to do things right.
nnoremap <up> <nop>
nnoremap <down> <nop>
nnoremap <left> <nop>
nnoremap <right> <nop>
inoremap <up> <nop>
inoremap <down> <nop>
inoremap <left> <nop>
inoremap <right> <nop>
nnoremap j gj
nnoremap k gk

" Rebind normal mode to jj
inoremap jj <ESC>

" Move code block
xnoremap K :move '<-2<CR>gv-gv
xnoremap J :move '>+1<CR>gv-gv

" Use alt + hjkl to resize windows
"nnoremap <M-j>    :resize -2<CR>
"nnoremap <M-k>    :resize +2<CR>
"nnoremap <M-h>    :vertical resize -2<CR>
"nnoremap <M-l>    :vertical resize +2<CR>

" Use TAB to move between bracket pairs
nnoremap <tab> %
vnoremap <tab> %

" Better tabbing
vnoremap < <gv
vnoremap > >gv

" gitsigns
nnoremap <leader>g :Gitsigns preview_hunk<CR>

" nerdcommenter
nmap <leader>c <plug>NERDCommenterToggle
vmap <leader>c <plug>NERDCommenterToggle<CR>gv

" fzf
nnoremap <leader>f :FZF<CR>
nnoremap <leader>r :Rg<CR>

" clear search
nnoremap <leader><space> :noh<cr>

" Better window navigation
"nnoremap <C-h> <C-w>h
"nnoremap <C-j> <C-w>j
"nnoremap <C-k> <C-w>k
"nnoremap <C-l> <C-w>l

" F6 toggles american english spell-checking
map <f6> :setlocal spell! spelllang=en_us<cr>

" CTRL + c and CTRL + P for copy and paste
vnoremap <C-c> "*y :let @+=@*<CR>
map <C-P> "+P
