set termguicolors                               " enable 24-bit color support in terminal
try
  colorscheme catppuccin " catppuccin-latte, catppuccin-frappe, catppuccin-macchiato, catppuccin-mocha
catch /^Vim\%((\a\+)\)\=:E185/
  " colorscheme not found - will be available after PlugInstall
endtry

highlight clear LineNr                          " set transparent line number column
highlight clear SignColumn                      " set transparent sign column
highlight clear Conceal                         " set transparent conceals
highlight clear CursorLine                      " set transparent cursorline
highlight clear CursorLineNR                    " set transparent cursorline line number
highlight Normal ctermbg=NONE guibg=NONE        " set transparent background with termguicolors enabled

autocmd InsertEnter * highlight CursorLine guibg=black
autocmd InsertLeave * highlight clear CursorLine


