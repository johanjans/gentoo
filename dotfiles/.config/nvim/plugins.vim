" Autodownload vim-plug if missing
let s:plug_path = stdpath('config') . '/autoload/plug.vim'
if empty(glob(s:plug_path))
   echo "Downloading junegunn/vim-plug to manage plugins..."
   silent execute '!mkdir -p ' . stdpath('config') . '/autoload'
   silent execute '!curl -fLo ' . s:plug_path . ' https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
endif

" Auto-install plugins on first start
let s:plugged_path = stdpath('config') . '/plugged'
if empty(glob(s:plugged_path))
   autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

" Plugins to install and use
call plug#begin(s:plugged_path)
  Plug 'neovim/nvim-lspconfig'
  Plug 'preservim/nerdcommenter'
  Plug 'lewis6991/gitsigns.nvim'
  Plug 'itchyny/lightline.vim'
  Plug 'mhinz/vim-startify'
  Plug 'ap/vim-css-color'
  Plug 'junegunn/fzf'
  Plug 'junegunn/fzf.vim'
  Plug 'airblade/vim-rooter' " project directory scope, consider .gitignore, etc in fzf
  Plug 'catppuccin/nvim', { 'as': 'catppuccin' }
  " nvim-cmp and sources
  Plug 'hrsh7th/nvim-cmp'
  Plug 'hrsh7th/cmp-nvim-lsp'
  Plug 'hrsh7th/cmp-buffer'
  Plug 'hrsh7th/cmp-path'
  Plug 'L3MON4D3/LuaSnip'
  Plug 'saadparwaiz1/cmp_luasnip'
  " nvim-tree
  Plug 'nvim-tree/nvim-tree.lua'
  Plug 'nvim-tree/nvim-web-devicons'
  " treesitter
  Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
call plug#end()

lua << EOF
-- catppuccin
local ok, catppuccin = pcall(require, "catppuccin")
if ok then
    catppuccin.setup({
        integrations = {
            cmp = true,
            gitsigns = true,
            nvimtree = true,
            treesitter = true,
        }
    })
end

-- gitsigns
local ok, gitsigns = pcall(require, "gitsigns")
if ok then
    gitsigns.setup({
        signs = {
            add          = { text = '│' },
            change       = { text = '│' },
            delete       = { text = '_' },
            topdelete    = { text = '‾' },
            changedelete = { text = '~' },
        },
        signcolumn = true,
        numhl = false,
        linehl = false,
    })
end

-- nvim-tree
local ok, nvimtree = pcall(require, "nvim-tree")
if ok then
    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1
    nvimtree.setup({
        view = { width = 30 },
        renderer = { group_empty = true },
        filters = { dotfiles = false },
    })
end

-- treesitter
local ok, treesitter = pcall(require, "nvim-treesitter.configs")
if ok then
    treesitter.setup({
        ensure_installed = { "lua", "vim", "vimdoc", "javascript", "typescript", "python", "html", "css" },
        sync_install = false,
        auto_install = true,
        highlight = { enable = true },
        indent = { enable = true },
    })
end

-- nvim-cmp
local cmp_ok, cmp = pcall(require, "cmp")
local luasnip_ok, luasnip = pcall(require, "luasnip")
if cmp_ok and luasnip_ok then
    cmp.setup({
        snippet = {
            expand = function(args)
                luasnip.lsp_expand(args.body)
            end,
        },
        mapping = cmp.mapping.preset.insert({
            ['<C-b>'] = cmp.mapping.scroll_docs(-4),
            ['<C-f>'] = cmp.mapping.scroll_docs(4),
            ['<C-Space>'] = cmp.mapping.complete(),
            ['<C-e>'] = cmp.mapping.abort(),
            ['<CR>'] = cmp.mapping.confirm({ select = true }),
        }),
        sources = cmp.config.sources({
            { name = 'nvim_lsp' },
            { name = 'luasnip' },
        }, {
            { name = 'buffer' },
            { name = 'path' },
        }),
    })
end

-- nvim-lspconfig
local lspconfig_ok, lspconfig = pcall(require, "lspconfig")
local cmp_lsp_ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
if lspconfig_ok then
    local capabilities = vim.lsp.protocol.make_client_capabilities()
    if cmp_lsp_ok then
        capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
    end

    local on_attach = function(client, bufnr)
        local opts = { noremap = true, silent = true, buffer = bufnr }
        vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, opts)
        vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
        vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
        vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, opts)
        vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, opts)
        vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, opts)
        vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, opts)
        vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
        vim.keymap.set('n', '<leader>d', vim.diagnostic.open_float, opts)
        vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, opts)
        vim.keymap.set('n', ']d', vim.diagnostic.goto_next, opts)
    end

    -- Add language servers here as needed, e.g.:
    -- lspconfig.ts_ls.setup({ capabilities = capabilities, on_attach = on_attach })
    -- lspconfig.pyright.setup({ capabilities = capabilities, on_attach = on_attach })
    -- lspconfig.lua_ls.setup({ capabilities = capabilities, on_attach = on_attach })
end
EOF

" nerdcommenter
let g:NERDCreateDefaultMappings = 0
let g:NERDSpaceDelims = 1
let g:NERDCompactSexyComs = 1
let g:NERDDefaultAlign = 'left'
let g:NERDCommentEmptyLines = 1
let g:NERDTrimTrailingWhitespace = 1
let g:NERDAltDelims_java = 1
let g:NERDCustomDelimiters = { 'c': { 'left': '/**','right': '*/' } }
let g:NERDToggleCheckAllLines = 1

" lightline
let g:lightline = { 'colorscheme': 'catppuccin' }

" startify
let g:startify_files_number = 18
let g:startify_lists = [ { 'type': 'dir', 'header': ['   Recent files'] }, { 'type': 'sessions', 'header': ['   Saved sessions'] }, ]
let g:startify_custom_header = [ '                        _',
  \ ' .____   ___  _____   _(_)____ ___',
  \ ' |  _ \ / _ \/ _ \ \ / / |  _ ` _ \',
  \ ' | | | |  __/ (_) \ V /| | | | | | |',
  \ ' |_| |_|\___|\___/ \_/ |_|_| |_| |_|',
  \ ]
